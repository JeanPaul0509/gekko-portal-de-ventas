-- =====================================================================
--  APP DE SORTEOS — Esquema completo para Supabase
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. PERFILES (un perfil por usuario, con su rol)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  phone      text unique not null,
  role       text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now()
);

-- Cada usuario nuevo SIEMPRE nace como 'user' (común).
-- Nadie puede volverse admin desde la app: solo tú desde Supabase.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, phone, role)
  values (
    new.id,
    split_part(new.email, '@', 1),   -- el celular sale del "correo" interno
    'user'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

alter table public.profiles enable row level security;
drop policy if exists "ver mi perfil" on public.profiles;
create policy "ver mi perfil" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());
-- Sin políticas de insert/update/delete: el rol NO se puede cambiar desde la app.

-- ---------------------------------------------------------------------
-- 2. SORTEOS
-- ---------------------------------------------------------------------
create table if not exists public.raffles (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  specs         text,                       -- una especificación por línea
  image_url     text,
  icon          text not null default '🎁',
  price         numeric(10,2) not null default 0 check (price >= 0),
  total_tickets int  not null check (total_tickets between 1 and 10000),
  status        text not null default 'active' check (status in ('active', 'finished')),
  draw_date     date,
  created_at    timestamptz not null default now()
);

alter table public.raffles enable row level security;
drop policy if exists "todos ven sorteos" on public.raffles;
drop policy if exists "admin crea sorteos" on public.raffles;
drop policy if exists "admin edita sorteos" on public.raffles;
drop policy if exists "admin borra sorteos" on public.raffles;
create policy "todos ven sorteos"   on public.raffles for select to authenticated using (true);
create policy "admin crea sorteos"  on public.raffles for insert to authenticated with check (public.is_admin());
create policy "admin edita sorteos" on public.raffles for update to authenticated using (public.is_admin());
create policy "admin borra sorteos" on public.raffles for delete to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 3. TICKETS (números)
--    available = verde  |  reserved = amarillo  |  sold = gris
-- ---------------------------------------------------------------------
create table if not exists public.tickets (
  id          bigint generated always as identity primary key,
  raffle_id   uuid not null references public.raffles(id) on delete cascade,
  number      int  not null,
  status      text not null default 'available' check (status in ('available', 'reserved', 'sold')),
  user_id     uuid references auth.users(id) on delete set null,
  buyer_name  text,
  buyer_phone text,
  reserved_at timestamptz,
  sold_at     timestamptz,
  unique (raffle_id, number)
);
create index if not exists tickets_raffle_status_idx on public.tickets (raffle_id, status);

-- Al crear un sorteo se generan automáticamente sus números 1..N
create or replace function public.create_raffle_tickets()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.tickets (raffle_id, number)
  select new.id, g from generate_series(1, new.total_tickets) g;
  return new;
end;
$$;

drop trigger if exists after_raffle_insert on public.raffles;
create trigger after_raffle_insert
  after insert on public.raffles
  for each row execute function public.create_raffle_tickets();

alter table public.tickets enable row level security;
drop policy if exists "todos ven tickets" on public.tickets;
create policy "todos ven tickets" on public.tickets for select to authenticated using (true);
-- Los usuarios comunes solo pueden ver número y estado (NO nombres ni celulares de otros).
revoke all on public.tickets from anon, authenticated;
grant select (id, raffle_id, number, status) on public.tickets to authenticated;
-- Todas las escrituras pasan por las funciones de abajo.

-- ---------------------------------------------------------------------
-- 4. FUNCIONES
-- ---------------------------------------------------------------------

-- Reservar: máx. 5 por compra y máx. 5 en espera por persona. Todo o nada.
create or replace function public.reserve_tickets(p_raffle_id uuid, p_numbers int[], p_name text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_wanted  int;
  v_pending int;
  v_done    int;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_numbers is null or coalesce(array_length(p_numbers, 1), 0) = 0 then
    raise exception 'Elige al menos un número';
  end if;
  select count(distinct x) into v_wanted from unnest(p_numbers) x;
  if v_wanted > 5 then raise exception 'Máximo 5 números por compra'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if not exists (select 1 from raffles where id = p_raffle_id and status = 'active') then
    raise exception 'Este sorteo ya no está activo';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos al mismo tiempo)
  select phone into v_phone from profiles where id = auth.uid() for update;

  select count(*) into v_pending
    from tickets
   where raffle_id = p_raffle_id and user_id = auth.uid() and status = 'reserved';

  if v_pending + v_wanted > 5 then
    if v_pending >= 5 then
      raise exception 'Ya tienes 5 números esperando confirmación de pago. Podrás pedir más cuando confirmemos tu pago.';
    end if;
    raise exception 'Tienes % número(s) esperando confirmación. Solo puedes pedir % más por ahora.', v_pending, 5 - v_pending;
  end if;

  update tickets
     set status = 'reserved', user_id = auth.uid(), buyer_name = trim(p_name),
         buyer_phone = v_phone, reserved_at = now(), sold_at = null
   where raffle_id = p_raffle_id and number = any(p_numbers) and status = 'available';
  get diagnostics v_done = row_count;

  if v_done <> v_wanted then
    raise exception 'Alguno de esos números acaba de ser tomado por otra persona. Elige otros.';
  end if;
end;
$$;

-- Conteos por sorteo (incluye cuántas personas distintas compraron)
create function public.raffle_counts()
returns table (raffle_id uuid, available bigint, reserved bigint, sold bigint, buyers bigint)
language sql stable security definer set search_path = public as $$
  select t.raffle_id,
         count(*) filter (where t.status = 'available'),
         count(*) filter (where t.status = 'reserved'),
         count(*) filter (where t.status = 'sold'),
         count(distinct coalesce(t.user_id::text, t.buyer_phone, t.buyer_name)) filter (where t.status = 'sold')
    from tickets t
   group by t.raffle_id;
$$;

-- Mis números (usuario común)
create or replace function public.my_tickets()
returns table (raffle_id uuid, raffle_title text, raffle_icon text, price numeric,
               number int, total_tickets int, status text, buyer_name text)
language sql stable security definer set search_path = public as $$
  select r.id, r.title, r.icon, r.price, t.number, r.total_tickets, t.status, t.buyer_name
    from tickets t join raffles r on r.id = t.raffle_id
   where t.user_id = auth.uid()
   order by r.created_at desc, t.number;
$$;

-- ADMIN: ver todos los tickets con datos del comprador
create or replace function public.admin_list_tickets(p_raffle_id uuid)
returns setof public.tickets
language sql stable security definer set search_path = public as $$
  select * from tickets where raffle_id = p_raffle_id and public.is_admin() order by number;
$$;

-- ADMIN: cambiar estado (gris = pagado, verde = liberar, amarillo = reservado)
create or replace function public.admin_set_ticket_status(p_ticket_ids bigint[], p_status text, p_name text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if p_status = 'available' then
    update tickets set status = 'available', user_id = null, buyer_name = null, buyer_phone = null,
                       reserved_at = null, sold_at = null
     where id = any(p_ticket_ids);
  elsif p_status = 'sold' then
    update tickets set status = 'sold', sold_at = now(),
                       buyer_name = coalesce(nullif(trim(p_name), ''), buyer_name),
                       reserved_at = coalesce(reserved_at, now())
     where id = any(p_ticket_ids);
  elsif p_status = 'reserved' then
    update tickets set status = 'reserved', sold_at = null,
                       buyer_name = coalesce(nullif(trim(p_name), ''), buyer_name),
                       reserved_at = coalesce(reserved_at, now())
     where id = any(p_ticket_ids);
  else
    raise exception 'Estado inválido';
  end if;
end;
$$;

revoke execute on function public.reserve_tickets(uuid, int[], text) from public, anon;
revoke execute on function public.raffle_counts() from public, anon;
revoke execute on function public.my_tickets() from public, anon;
revoke execute on function public.admin_list_tickets(uuid) from public, anon;
revoke execute on function public.admin_set_ticket_status(bigint[], text, text) from public, anon;
grant execute on function public.reserve_tickets(uuid, int[], text) to authenticated;
grant execute on function public.raffle_counts() to authenticated;
grant execute on function public.my_tickets() to authenticated;
grant execute on function public.admin_list_tickets(uuid) to authenticated;
grant execute on function public.admin_set_ticket_status(bigint[], text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. SGEKKOGE: fotos de los premios
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('raffle-images', 'raffle-images', true)
on conflict (id) do nothing;

drop policy if exists "admin sube imagenes" on storage.objects;
drop policy if exists "admin edita imagenes" on storage.objects;
drop policy if exists "admin borra imagenes" on storage.objects;
create policy "admin sube imagenes" on storage.objects
  for insert to authenticated with check (bucket_id = 'raffle-images' and public.is_admin());
create policy "admin edita imagenes" on storage.objects
  for update to authenticated using (bucket_id = 'raffle-images' and public.is_admin());
create policy "admin borra imagenes" on storage.objects
  for delete to authenticated using (bucket_id = 'raffle-images' and public.is_admin());

-- =====================================================================
--  CREAR UN ADMINISTRADOR (hazlo después de crear el usuario en
--  Authentication > Users > Add user, con correo 9XXXXXXXX@celular.sorteos.app)
--
--  update public.profiles set role = 'admin' where phone = '987654321';
-- =====================================================================

-- =====================================================================
--  GRUPO DE WHATSAPP POR SORTEO
--  El enlace se guarda en una tabla aparte que los usuarios NO pueden leer.
--  Solo lo reciben quienes tienen al menos un número PAGADO en ese sorteo.
--  Cómo usarlo: Supabase > SQL Editor > pega todo > Run
-- =====================================================================

create table if not exists public.raffle_secrets (
  raffle_id          uuid primary key references public.raffles(id) on delete cascade,
  whatsapp_group_url text
);

alter table public.raffle_secrets enable row level security;
drop policy if exists "admin gestiona secretos" on public.raffle_secrets;
create policy "admin gestiona secretos" on public.raffle_secrets
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Enlace del grupo para el usuario actual (null si aún no tiene números pagados)
create or replace function public.my_group_link(p_raffle_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select s.whatsapp_group_url
    from raffle_secrets s
   where s.raffle_id = p_raffle_id
     and exists (select 1 from tickets t
                  where t.raffle_id = p_raffle_id and t.user_id = auth.uid() and t.status = 'sold');
$$;

-- "Mis números" ahora también devuelve el enlace (solo en números pagados)
drop function if exists public.my_tickets();
create function public.my_tickets()
returns table (raffle_id uuid, raffle_title text, raffle_icon text, price numeric,
               number int, total_tickets int, status text, buyer_name text, group_url text)
language sql stable security definer set search_path = public as $$
  select r.id, r.title, r.icon, r.price, t.number, r.total_tickets, t.status, t.buyer_name,
         case when t.status = 'sold' then s.whatsapp_group_url end
    from tickets t
    join raffles r on r.id = t.raffle_id
    left join raffle_secrets s on s.raffle_id = r.id
   where t.user_id = auth.uid()
   order by r.created_at desc, t.number;
$$;

revoke execute on function public.my_group_link(uuid) from public, anon;
revoke execute on function public.my_tickets() from public, anon;
grant execute on function public.my_group_link(uuid) to authenticated;
grant execute on function public.my_tickets() to authenticated;

-- =====================================================================
--  REDES SOCIALES (WhatsApp, Instagram, TikTok) — una sola fila global
--  Cómo usarlo: Supabase > SQL Editor > pega todo > Run
-- =====================================================================
create table if not exists public.site_settings (
  id            int primary key default 1 check (id = 1),
  whatsapp_url  text,
  instagram_url text,
  tiktok_url    text,
  updated_at    timestamptz not null default now()
);
insert into public.site_settings (id) values (1) on conflict (id) do nothing;

alter table public.site_settings enable row level security;
drop policy if exists "todos ven redes" on public.site_settings;
drop policy if exists "admin edita redes" on public.site_settings;
-- Visibles también en el login (sin sesión)
create policy "todos ven redes" on public.site_settings for select to anon, authenticated using (true);
create policy "admin edita redes" on public.site_settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select on public.site_settings to anon, authenticated;
grant update on public.site_settings to authenticated;
-- =====================================================================
--  LÍMITES DE TEXTO (protección también en la base de datos)
--  "not valid" = no revisa los datos que ya existen, solo los nuevos/editados.
--  Cómo usarlo: Supabase > SQL Editor > pega todo > Run
-- =====================================================================
alter table public.raffles drop constraint if exists raffles_title_len;
alter table public.raffles drop constraint if exists raffles_description_len;
alter table public.raffles drop constraint if exists raffles_specs_len;
alter table public.tickets drop constraint if exists tickets_buyer_name_len;

alter table public.raffles add constraint raffles_title_len
  check (char_length(title) between 1 and 80) not valid;
alter table public.raffles add constraint raffles_description_len
  check (description is null or char_length(description) <= 1000) not valid;
alter table public.raffles add constraint raffles_specs_len
  check (specs is null or char_length(specs) <= 1000) not valid;
alter table public.tickets add constraint tickets_buyer_name_len
  check (buyer_name is null or char_length(buyer_name) <= 60) not valid;
-- =====================================================================
--  GANADOR PUBLICADO + RESTABLECER CONTRASEÑA + TÉRMINOS Y CONDICIONES
--  Cómo usarlo: Supabase > SQL Editor > pega todo > Run
-- =====================================================================

-- ---------- 1. Ganador del sorteo ----------
alter table public.raffles add column if not exists winner_number  int;
alter table public.raffles add column if not exists winner_display text;   -- "Juan P." (nombre abreviado)
alter table public.raffles add column if not exists draw_video_url text;   -- link al video del sorteo en vivo
alter table public.raffles add column if not exists drawn_at       timestamptz;

-- Marca el ganador (debe ser un número PAGADO) y finaliza el sorteo.
-- p_number = null quita el ganador (por si se equivocó).
create or replace function public.admin_set_winner(p_raffle_id uuid, p_number int, p_video text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_name  text;
  v_parts text[];
  v_disp  text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if p_number is null then
    update raffles set winner_number = null, winner_display = null, draw_video_url = null, drawn_at = null
     where id = p_raffle_id;
    return null;
  end if;

  select buyer_name into v_name from tickets
   where raffle_id = p_raffle_id and number = p_number and status = 'sold';
  if not found then
    raise exception 'El número % no está pagado. Solo un número pagado puede ganar.', p_number;
  end if;

  v_parts := regexp_split_to_array(trim(coalesce(v_name, '')), '\s+');
  v_disp := initcap(v_parts[1]);
  if array_length(v_parts, 1) > 1 and v_parts[2] <> '' then
    v_disp := v_disp || ' ' || upper(left(v_parts[2], 1)) || '.';
  end if;

  update raffles
     set winner_number = p_number,
         winner_display = nullif(v_disp, ''),
         draw_video_url = nullif(trim(coalesce(p_video, '')), ''),
         drawn_at = now(),
         status = 'finished'
   where id = p_raffle_id;
  return v_disp;
end;
$$;

-- ---------- 2. Restablecer contraseña de un usuario (solo admin) ----------
create or replace function public.admin_reset_password(p_phone text, p_new_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_phone ~ '^519\d{8}$' then v_phone := substr(v_phone, 3); end if;
  if v_phone !~ '^9\d{8}$' then raise exception 'Celular inválido'; end if;
  if char_length(coalesce(p_new_password, '')) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
         updated_at = now()
   where email = v_phone || '@celular.sorteos.app';
  if not found then raise exception 'No hay ninguna cuenta con el celular %', v_phone; end if;
end;
$$;

-- ---------- 3. Términos y condiciones (editables por el admin) ----------
alter table public.site_settings add column if not exists terms_text text;
alter table public.site_settings add column if not exists terms_updated_at timestamptz;

revoke execute on function public.admin_set_winner(uuid, int, text) from public, anon;
revoke execute on function public.admin_reset_password(text, text) from public, anon;
grant execute on function public.admin_set_winner(uuid, int, text) to authenticated;
grant execute on function public.admin_reset_password(text, text) to authenticated;

-- =====================================================================
--  VERIFICACIÓN DE CELULAR POR WHATSAPP (verificación inversa)
--  La persona envía un mensaje con un código al número de verificación;
--  Meta avisa a la app y el celular queda verificado. No se envía nada
--  hacia la persona, así que no cuesta.
--  Queda APAGADA por defecto (require_phone_verification = false): nadie
--  pierde la posibilidad de comprar hasta que tú la enciendas.
--  Cómo usarlo: Supabase > SQL Editor > pega todo > Run
-- =====================================================================

-- ---------- 1. Marca de verificado en el perfil ----------
alter table public.profiles add column if not exists verified_at timestamptz;

-- ---------- 2. Interruptor global (lo enciendes tú cuando todo funcione) ----------
alter table public.site_settings
  add column if not exists require_phone_verification boolean not null default false;

-- ---------- 3. Códigos pendientes (nadie puede leerlos desde la app) ----------
create table if not exists public.phone_verifications (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  code       text not null unique,
  expires_at timestamptz not null
);
alter table public.phone_verifications enable row level security;
revoke all on public.phone_verifications from anon, authenticated;

-- ---------- 4. Pedir un código (usuario con sesión) ----------
-- Devuelve el código (ej. GT-4F8A21), o null si el celular ya está verificado.
-- Si ya tiene un código vigente, devuelve el mismo.
create or replace function public.start_phone_verification()
returns text language plpgsql security definer set search_path = public as $$
declare
  v_code text;
  v_try  int := 0;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if exists (select 1 from profiles where id = auth.uid() and verified_at is not null) then
    return null;
  end if;

  select code into v_code
    from phone_verifications
   where user_id = auth.uid() and expires_at > now();
  if v_code is not null then return v_code; end if;

  loop
    v_try := v_try + 1;
    v_code := 'GT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    begin
      insert into phone_verifications (user_id, code, expires_at)
      values (auth.uid(), v_code, now() + interval '15 minutes')
      on conflict (user_id) do update
        set code = excluded.code, expires_at = excluded.expires_at;
      return v_code;
    exception when unique_violation then
      if v_try >= 5 then raise; end if;
    end;
  end loop;
end;
$$;

-- ---------- 5. Confirmar (SOLO la llama el servidor con la llave secreta) ----------
-- Verifica que el mensaje vino del celular de la cuenta Y trae su código vigente.
create or replace function public.confirm_phone_verification(p_phone text, p_code text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
begin
  select v.user_id into v_user
    from phone_verifications v
    join profiles p on p.id = v.user_id
   where v.code = upper(trim(p_code))
     and v.expires_at > now()
     and p.phone = p_phone
   for update of v;

  if v_user is null then return false; end if;

  update profiles set verified_at = now() where id = v_user and verified_at is null;
  delete from phone_verifications where user_id = v_user;
  return true;
end;
$$;

revoke execute on function public.start_phone_verification() from public, anon;
revoke execute on function public.confirm_phone_verification(text, text) from public, anon, authenticated;
grant execute on function public.start_phone_verification() to authenticated;
grant execute on function public.confirm_phone_verification(text, text) to service_role;

-- ---------- 6. Comprar exige celular verificado (solo si el interruptor está encendido) ----------
-- Igual que antes (límites de 5), más la revisión de verificación. El admin no la necesita.
create or replace function public.reserve_tickets(p_raffle_id uuid, p_numbers int[], p_name text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_wanted  int;
  v_pending int;
  v_done    int;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;

  if coalesce((select require_phone_verification from site_settings where id = 1), false)
     and not exists (select 1 from profiles
                      where id = auth.uid() and (verified_at is not null or role = 'admin')) then
    raise exception 'Verifica tu celular por WhatsApp antes de comprar.';
  end if;

  if p_numbers is null or coalesce(array_length(p_numbers, 1), 0) = 0 then
    raise exception 'Elige al menos un número';
  end if;
  select count(distinct x) into v_wanted from unnest(p_numbers) x;
  if v_wanted > 5 then raise exception 'Máximo 5 números por compra'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if not exists (select 1 from raffles where id = p_raffle_id and status = 'active') then
    raise exception 'Este sorteo ya no está activo';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos al mismo tiempo)
  select phone into v_phone from profiles where id = auth.uid() for update;

  select count(*) into v_pending
    from tickets
   where raffle_id = p_raffle_id and user_id = auth.uid() and status = 'reserved';

  if v_pending + v_wanted > 5 then
    if v_pending >= 5 then
      raise exception 'Ya tienes 5 números esperando confirmación de pago. Podrás pedir más cuando confirmemos tu pago.';
    end if;
    raise exception 'Tienes % número(s) esperando confirmación. Solo puedes pedir % más por ahora.', v_pending, 5 - v_pending;
  end if;

  update tickets
     set status = 'reserved', user_id = auth.uid(), buyer_name = trim(p_name),
         buyer_phone = v_phone, reserved_at = now(), sold_at = null
   where raffle_id = p_raffle_id and number = any(p_numbers) and status = 'available';
  get diagnostics v_done = row_count;

  if v_done <> v_wanted then
    raise exception 'Alguno de esos números acaba de ser tomado por otra persona. Elige otros.';
  end if;
end;
$$;

revoke execute on function public.reserve_tickets(uuid, int[], text) from public, anon;
grant execute on function public.reserve_tickets(uuid, int[], text) to authenticated;

-- =====================================================================
--  CUANDO TODO FUNCIONE (Meta conectado y probado), enciende la regla:
--    update public.site_settings set require_phone_verification = true where id = 1;
--  Para apagarla otra vez:
--    update public.site_settings set require_phone_verification = false where id = 1;
-- =====================================================================

-- =====================================================================
--  GEKKO: TIENDA (productos, pedidos y stock)
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PRODUCTOS (los crea y edita solo el admin)
-- ---------------------------------------------------------------------
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(trim(name)) between 1 and 80),
  description text check (char_length(description) <= 500),
  category    text not null default 'pollo' check (category in ('pollo', 'promos', 'belleza')),
  price       numeric(10,2) not null check (price >= 0 and price <= 100000),
  stock       int not null default 0 check (stock >= 0 and stock <= 100000),
  image_url   text,
  active      boolean not null default true,   -- false = oculto en la tienda
  sort        int not null default 0,          -- orden dentro de su categoría
  created_at  timestamptz not null default now()
);

alter table public.products enable row level security;
drop policy if exists "ver productos" on public.products;
drop policy if exists "admin crea productos" on public.products;
drop policy if exists "admin edita productos" on public.products;
drop policy if exists "admin borra productos" on public.products;
create policy "ver productos" on public.products
  for select to authenticated using (active or public.is_admin());
create policy "admin crea productos" on public.products
  for insert to authenticated with check (public.is_admin());
create policy "admin edita productos" on public.products
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin borra productos" on public.products
  for delete to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 2. PEDIDOS
--    pending = esperando pago | paid = pagado | delivered = entregado | cancelled
-- ---------------------------------------------------------------------
create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  order_no     bigint generated always as identity,
  user_id      uuid references auth.users(id) on delete set null,
  buyer_name   text not null,
  buyer_phone  text not null,
  address      text,
  note         text,
  total        numeric(10,2) not null default 0,
  status       text not null default 'pending' check (status in ('pending', 'paid', 'delivered', 'cancelled')),
  created_at   timestamptz not null default now(),
  paid_at      timestamptz,
  delivered_at timestamptz
);
create index if not exists orders_user_idx on public.orders (user_id, created_at desc);
create index if not exists orders_status_idx on public.orders (status, created_at desc);

-- Cada línea guarda el nombre y el precio del momento (si cambias el precio después, el pedido no cambia)
create table if not exists public.order_items (
  id         bigint generated always as identity primary key,
  order_id   uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  name       text not null,
  price      numeric(10,2) not null,
  qty        int not null check (qty > 0)
);
create index if not exists order_items_order_idx on public.order_items (order_id);

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
drop policy if exists "ver mis pedidos" on public.orders;
drop policy if exists "ver items de mis pedidos" on public.order_items;
create policy "ver mis pedidos" on public.orders
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "ver items de mis pedidos" on public.order_items
  for select to authenticated using (
    exists (select 1 from public.orders o
             where o.id = order_id and (o.user_id = auth.uid() or public.is_admin()))
  );
-- Nadie escribe directo: todo pasa por las funciones de abajo.
revoke all on public.orders from anon, authenticated;
revoke all on public.order_items from anon, authenticated;
grant select on public.orders to authenticated;
grant select on public.order_items to authenticated;

-- ---------------------------------------------------------------------
-- 3. FUNCIONES
-- ---------------------------------------------------------------------

-- Hacer un pedido: revisa el stock, lo descuenta y guarda el pedido. Todo o nada.
-- p_items = [{"product_id": "...", "qty": 2}, ...]
create or replace function public.create_order(p_items jsonb, p_name text, p_address text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.orders%rowtype;
  v_item    record;
  v_prod    public.products%rowtype;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe tu dirección o referencia de entrega'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  select count(*) into v_pending from orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into orders (user_id, buyer_name, buyer_phone, address, note)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''))
  returning * into v_order;

  for v_item in
    select (e->>'product_id')::uuid as product_id, sum((e->>'qty')::int) as qty
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    if v_item.product_id is null or v_item.qty < 1 or v_item.qty > 50 then
      raise exception 'Cantidad inválida';
    end if;
    select * into v_prod from products where id = v_item.product_id and active for update;
    if not found then raise exception 'Uno de los productos ya no está disponible.'; end if;
    if v_prod.stock < v_item.qty then
      if v_prod.stock = 0 then
        raise exception '% se agotó. Quítalo del carrito para continuar.', v_prod.name;
      end if;
      raise exception 'De % solo quedan %. Baja la cantidad para continuar.', v_prod.name, v_prod.stock;
    end if;

    update products set stock = stock - v_item.qty where id = v_prod.id;
    insert into order_items (order_id, product_id, name, price, qty)
    values (v_order.id, v_prod.id, v_prod.name, v_prod.price, v_item.qty);

    v_total := v_total + v_prod.price * v_item.qty;
    v_lines := v_lines || jsonb_build_object('name', v_prod.name, 'price', v_prod.price, 'qty', v_item.qty);
  end loop;

  update orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total, 'items', v_lines);
end;
$$;

-- El cliente cancela su propio pedido mientras siga esperando pago (devuelve el stock)
create or replace function public.cancel_my_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_order public.orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  select * into v_order from orders where id = p_order_id and user_id = auth.uid() for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if v_order.status <> 'pending' then
    raise exception 'Solo se puede cancelar un pedido que aún no se pagó. Escríbenos por WhatsApp.';
  end if;

  update products p set stock = p.stock + i.qty
    from order_items i
   where i.order_id = v_order.id and p.id = i.product_id;
  update orders set status = 'cancelled' where id = v_order.id;
end;
$$;

-- ADMIN: cambiar el estado de un pedido (cancelar devuelve el stock)
create or replace function public.admin_set_order_status(p_order_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare v_order public.orders%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_status not in ('pending', 'paid', 'delivered', 'cancelled') then raise exception 'Estado inválido'; end if;

  select * into v_order from orders where id = p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if v_order.status = p_status then return; end if;
  if v_order.status = 'cancelled' then
    raise exception 'Un pedido cancelado no se puede reactivar. Pide al cliente que haga uno nuevo.';
  end if;

  if p_status = 'cancelled' then
    update products p set stock = p.stock + i.qty
      from order_items i
     where i.order_id = v_order.id and p.id = i.product_id;
    update orders set status = 'cancelled' where id = v_order.id;
  elsif p_status = 'paid' then
    update orders set status = 'paid', paid_at = coalesce(paid_at, now()), delivered_at = null
     where id = v_order.id;
  elsif p_status = 'delivered' then
    update orders set status = 'delivered', paid_at = coalesce(paid_at, now()), delivered_at = now()
     where id = v_order.id;
  else
    update orders set status = 'pending', paid_at = null, delivered_at = null where id = v_order.id;
  end if;
end;
$$;

revoke execute on function public.create_order(jsonb, text, text, text) from public, anon;
revoke execute on function public.cancel_my_order(uuid) from public, anon;
revoke execute on function public.admin_set_order_status(uuid, text) from public, anon;
grant execute on function public.create_order(jsonb, text, text, text) to authenticated;
grant execute on function public.cancel_my_order(uuid) to authenticated;
grant execute on function public.admin_set_order_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. PRODUCTOS DEL FLYER (solo si aún no hay ninguno). Stock en 0: el admin
--    sube la foto y pone las unidades desde Admin > Productos.
-- ---------------------------------------------------------------------
insert into public.products (name, description, category, price, stock, sort)
select * from (values
  ('Pecho',       'Pollo aderezado, listo para cocinar',      'pollo',  6.00::numeric, 0, 1),
  ('Pierna',      'Pollo aderezado, listo para cocinar',      'pollo',  6.00::numeric, 0, 2),
  ('Ala',         'Pollo aderezado, listo para cocinar',      'pollo',  5.50::numeric, 0, 3),
  ('Entrepierna', 'Pollo aderezado, listo para cocinar',      'pollo',  5.00::numeric, 0, 4),
  ('El banquete entero',  'Pollo entero · 8 piezas aderezadas', 'promos', 40.00::numeric, 0, 1),
  ('La mitad ganadora',   'Medio pollo · 4 piezas aderezadas',  'promos', 21.00::numeric, 0, 2),
  ('Dúo dinámico',        'Pecho + pierna',                     'promos', 11.00::numeric, 0, 3),
  ('El vuelo sabroso',    'Pecho + ala',                        'promos', 10.50::numeric, 0, 4),
  ('El combo poderoso',   'Entrepierna + ala',                  'promos', 10.00::numeric, 0, 5)
) as v(name, description, category, price, stock, sort)
where not exists (select 1 from public.products);
-- ===== 010 · Oferta de los jueves =====
create or replace function public.is_promo_day()
returns boolean language sql stable set search_path = public as $$
  select extract(isodow from (now() at time zone 'America/Lima')) = 4;
$$;

-- Para que la app muestre el precio correcto: ¿es jueves? y ¿cuántas unidades de cada pieza ya pidió hoy?
create or replace function public.promo_info()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_used jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('active', false, 'used', '{}'::jsonb); end if;
  select coalesce(jsonb_object_agg(product_id, qty), '{}'::jsonb) into v_used
  from (
    select oi.product_id, sum(oi.qty)::int as qty
      from order_items oi
      join orders o on o.id = oi.order_id
      join products p on p.id = oi.product_id
     where o.user_id = auth.uid()
       and o.status <> 'cancelled'
       and p.category = 'pollo'
       and (o.created_at at time zone 'America/Lima')::date = (now() at time zone 'America/Lima')::date
     group by oi.product_id
  ) t;
  return jsonb_build_object('active', public.is_promo_day(), 'used', v_used);
end;
$$;
grant execute on function public.promo_info() to authenticated;

create or replace function public.create_order(p_items jsonb, p_name text, p_address text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.orders%rowtype;
  v_item    record;
  v_prod    public.products%rowtype;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
  v_promo   boolean := public.is_promo_day();
  v_prev    int;
  v_n5      int;
  v_n6      int;
  v_nr      int;
  v_tier    record;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe tu dirección o referencia de entrega'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  select count(*) into v_pending from orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into orders (user_id, buyer_name, buyer_phone, address, note)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''))
  returning * into v_order;

  for v_item in
    select (e->>'product_id')::uuid as product_id, sum((e->>'qty')::int) as qty
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    if v_item.product_id is null or v_item.qty < 1 or v_item.qty > 50 then
      raise exception 'Cantidad inválida';
    end if;
    select * into v_prod from products where id = v_item.product_id and active for update;
    if not found then raise exception 'Uno de los productos ya no está disponible.'; end if;
    if v_prod.stock < v_item.qty then
      if v_prod.stock = 0 then
        raise exception '% se agotó. Quítalo del carrito para continuar.', v_prod.name;
      end if;
      raise exception 'De % solo quedan %. Baja la cantidad para continuar.', v_prod.name, v_prod.stock;
    end if;

    update products set stock = stock - v_item.qty where id = v_prod.id;

    -- Reparto de precios: S/5 la 1.ª, S/6 la 2.ª, normal desde la 3.ª (solo piezas, solo jueves)
    v_n5 := 0; v_n6 := 0;
    if v_promo and v_prod.category = 'pollo' then
      select coalesce(sum(oi.qty), 0)::int into v_prev
        from order_items oi join orders o on o.id = oi.order_id
       where o.user_id = auth.uid() and o.status <> 'cancelled' and o.id <> v_order.id
         and oi.product_id = v_prod.id
         and (o.created_at at time zone 'America/Lima')::date = (now() at time zone 'America/Lima')::date;
      if v_prev = 0 then v_n5 := 1; end if;
      if v_prev <= 1 and v_prev + v_item.qty >= 2 then v_n6 := 1; end if;
    end if;
    v_nr := v_item.qty - v_n5 - v_n6;

    for v_tier in
      select * from (values
        (v_n5, least(v_prod.price, 5::numeric)),
        (v_n6, least(v_prod.price, 6::numeric)),
        (v_nr, v_prod.price)
      ) t(q, pr) where q > 0
    loop
      insert into order_items (order_id, product_id, name, price, qty)
      values (v_order.id, v_prod.id, v_prod.name, v_tier.pr, v_tier.q);
      v_total := v_total + v_tier.pr * v_tier.q;
      v_lines := v_lines || jsonb_build_object('name', v_prod.name, 'price', v_tier.pr, 'qty', v_tier.q);
    end loop;
  end loop;

  update orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total, 'items', v_lines);
end;
$$;

-- ===== 011 · Jueves: solo la 1.ª a S/5 =====
create or replace function public.create_order(p_items jsonb, p_name text, p_address text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.orders%rowtype;
  v_item    record;
  v_prod    public.products%rowtype;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
  v_promo   boolean := public.is_promo_day();
  v_prev    int;
  v_n5      int;
  v_nr      int;
  v_tier    record;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe tu dirección o referencia de entrega'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  select count(*) into v_pending from orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into orders (user_id, buyer_name, buyer_phone, address, note)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''))
  returning * into v_order;

  for v_item in
    select (e->>'product_id')::uuid as product_id, sum((e->>'qty')::int) as qty
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    if v_item.product_id is null or v_item.qty < 1 or v_item.qty > 50 then
      raise exception 'Cantidad inválida';
    end if;
    select * into v_prod from products where id = v_item.product_id and active for update;
    if not found then raise exception 'Uno de los productos ya no está disponible.'; end if;
    if v_prod.stock < v_item.qty then
      if v_prod.stock = 0 then
        raise exception '% se agotó. Quítalo del carrito para continuar.', v_prod.name;
      end if;
      raise exception 'De % solo quedan %. Baja la cantidad para continuar.', v_prod.name, v_prod.stock;
    end if;

    update products set stock = stock - v_item.qty where id = v_prod.id;

    -- Reparto de precios: S/5 la 1.ª del día, normal desde la 2.ª (solo piezas, solo jueves)
    v_n5 := 0;
    if v_promo and v_prod.category = 'pollo' then
      select coalesce(sum(oi.qty), 0)::int into v_prev
        from order_items oi join orders o on o.id = oi.order_id
       where o.user_id = auth.uid() and o.status <> 'cancelled' and o.id <> v_order.id
         and oi.product_id = v_prod.id
         and (o.created_at at time zone 'America/Lima')::date = (now() at time zone 'America/Lima')::date;
      if v_prev = 0 then v_n5 := 1; end if;
    end if;
    v_nr := v_item.qty - v_n5;

    for v_tier in
      select * from (values
        (v_n5, least(v_prod.price, 5::numeric)),
        (v_nr, v_prod.price)
      ) t(q, pr) where q > 0
    loop
      insert into order_items (order_id, product_id, name, price, qty)
      values (v_order.id, v_prod.id, v_prod.name, v_tier.pr, v_tier.q);
      v_total := v_total + v_tier.pr * v_tier.q;
      v_lines := v_lines || jsonb_build_object('name', v_prod.name, 'price', v_tier.pr, 'qty', v_tier.q);
    end loop;
  end loop;

  update orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total, 'items', v_lines);
end;
$$;


-- =====================================================================
--  GEKKO FOOD: pollo broaster, pedidos y cartilla de puntos
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez. Usa la MISMA base de datos de Gekko:
--  los usuarios (profiles) y el admin (is_admin) son los mismos.
--
--  Cartilla: cada pedido pagado suma 1 punto. Con 7 puntos, el siguiente
--  pedido es un REGALO (broaster con chaufa u hamburguesa) y no suma punto.
--  Después la cartilla vuelve a empezar. Los puntos se CALCULAN con los
--  pedidos, así que si un pedido se cancela, la cartilla se corrige sola.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CARTA (las piezas de broaster; las edita solo el admin)
-- ---------------------------------------------------------------------
create table if not exists public.food_items (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(trim(name)) between 1 and 60),
  price      numeric(10,2) not null check (price >= 0 and price <= 1000),
  active     boolean not null default true,   -- false = oculto (agotado)
  sort       int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.food_items enable row level security;
drop policy if exists "ver carta" on public.food_items;
drop policy if exists "admin crea carta" on public.food_items;
drop policy if exists "admin edita carta" on public.food_items;
drop policy if exists "admin borra carta" on public.food_items;
create policy "ver carta" on public.food_items
  for select to authenticated using (active or public.is_admin());
create policy "admin crea carta" on public.food_items
  for insert to authenticated with check (public.is_admin());
create policy "admin edita carta" on public.food_items
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin borra carta" on public.food_items
  for delete to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 2. PEDIDOS DE GEKKO FOOD
--    pending = esperando pago | paid = pagado | delivered = entregado | cancelled
--    is_reward = pedido de regalo de la cartilla (total 0, no suma punto)
-- ---------------------------------------------------------------------
create table if not exists public.food_orders (
  id           uuid primary key default gen_random_uuid(),
  order_no     bigint generated always as identity,
  user_id      uuid references auth.users(id) on delete set null,
  buyer_name   text not null,
  buyer_phone  text not null,
  address      text,
  note         text,
  total        numeric(10,2) not null default 0,
  is_reward    boolean not null default false,
  status       text not null default 'pending' check (status in ('pending', 'paid', 'delivered', 'cancelled')),
  created_at   timestamptz not null default now(),
  paid_at      timestamptz,
  delivered_at timestamptz
);
create index if not exists food_orders_user_idx on public.food_orders (user_id, created_at desc);
create index if not exists food_orders_status_idx on public.food_orders (status, created_at desc);

-- Cada línea guarda el nombre y el precio del momento. side = 'papa' (papa sola) o 'arroz' (con arroz)
create table if not exists public.food_order_items (
  id       bigint generated always as identity primary key,
  order_id uuid not null references public.food_orders(id) on delete cascade,
  item_id  uuid references public.food_items(id) on delete set null,
  name     text not null,
  side     text check (side in ('papa', 'arroz')),
  price    numeric(10,2) not null,
  qty      int not null check (qty > 0)
);
create index if not exists food_order_items_order_idx on public.food_order_items (order_id);

alter table public.food_orders enable row level security;
alter table public.food_order_items enable row level security;
drop policy if exists "ver mis pedidos food" on public.food_orders;
drop policy if exists "ver items de mis pedidos food" on public.food_order_items;
create policy "ver mis pedidos food" on public.food_orders
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "ver items de mis pedidos food" on public.food_order_items
  for select to authenticated using (
    exists (select 1 from public.food_orders o
             where o.id = order_id and (o.user_id = auth.uid() or public.is_admin()))
  );
-- Nadie escribe directo: todo pasa por las funciones de abajo.
revoke all on public.food_orders from anon, authenticated;
revoke all on public.food_order_items from anon, authenticated;
grant select on public.food_orders to authenticated;
grant select on public.food_order_items to authenticated;

-- ---------------------------------------------------------------------
-- 3. CARTILLA
-- ---------------------------------------------------------------------

-- Puntos de una persona = pedidos normales pagados/entregados
--                         - 7 por cada regalo pedido (sin contar los cancelados)
create or replace function public.food_points(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(0,
    (select count(*) from food_orders
      where user_id = p_user and not is_reward and status in ('paid', 'delivered'))
    - 7 * (select count(*) from food_orders
            where user_id = p_user and is_reward and status <> 'cancelled')
  )::int;
$$;

-- Mi cartilla: {"points": 0..7, "goal": 7, "reward_ready": true/false}
create or replace function public.food_card()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_points int;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  v_points := public.food_points(auth.uid());
  return jsonb_build_object('points', least(v_points, 7), 'goal', 7, 'reward_ready', v_points >= 7);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. FUNCIONES DE PEDIDOS
-- ---------------------------------------------------------------------

-- Hacer un pedido. p_items = [{"item_id": "...", "qty": 2, "side": "arroz"}, ...]
create or replace function public.create_food_order(p_items jsonb, p_name text, p_address text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.food_orders%rowtype;
  v_e       jsonb;
  v_item    public.food_items%rowtype;
  v_qty     int;
  v_side    text;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe tu dirección o referencia de entrega'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  select count(*) into v_pending from food_orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into food_orders (user_id, buyer_name, buyer_phone, address, note)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''))
  returning * into v_order;

  for v_e in select * from jsonb_array_elements(p_items) loop
    v_qty  := (v_e->>'qty')::int;
    v_side := v_e->>'side';
    if v_qty is null or v_qty < 1 or v_qty > 20 then raise exception 'Cantidad inválida'; end if;
    if v_side is null or v_side not in ('papa', 'arroz') then
      raise exception 'Elige papa sola o con arroz en cada pieza';
    end if;

    select * into v_item from food_items where id = (v_e->>'item_id')::uuid and active;
    if not found then raise exception 'Una de las piezas ya no está disponible. Quítala del carrito.'; end if;

    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, v_item.id, v_item.name, v_side, v_item.price, v_qty);

    v_total := v_total + v_item.price * v_qty;
    v_lines := v_lines || jsonb_build_object('name', v_item.name, 'side', v_side, 'price', v_item.price, 'qty', v_qty);
  end loop;

  update food_orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total, 'items', v_lines);
end;
$$;

-- Canjear el regalo de la cartilla (necesita 7 puntos).
-- p_choice = 'chaufa' (una pieza de broaster con chaufa; hay que elegir p_item_id) o 'hamburguesa'
create or replace function public.create_food_reward(p_choice text, p_item_id uuid, p_name text, p_address text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.food_orders%rowtype;
  v_item    public.food_items%rowtype;
  v_label   text;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_choice not in ('chaufa', 'hamburguesa') then raise exception 'Elige tu regalo'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe tu dirección o referencia de entrega'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;

  select phone into v_phone from profiles where id = auth.uid() for update;

  if public.food_points(auth.uid()) < 7 then
    raise exception 'Aún no completas tu cartilla de 7 pedidos.';
  end if;

  select count(*) into v_pending from food_orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás canjear tu regalo cuando confirmemos o canceles alguno.';
  end if;

  if p_choice = 'chaufa' then
    select * into v_item from food_items where id = p_item_id and active;
    if not found then raise exception 'Elige la pieza de tu broaster con chaufa'; end if;
    v_label := v_item.name || ' broaster con chaufa (regalo)';
  else
    v_label := 'Hamburguesa (regalo)';
  end if;

  -- El regalo no se paga: entra directo como "pagado" y no suma punto
  insert into food_orders (user_id, buyer_name, buyer_phone, address, note, total, is_reward, status, paid_at)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''), 0, true, 'paid', now())
  returning * into v_order;

  insert into food_order_items (order_id, item_id, name, side, price, qty)
  values (v_order.id, case when p_choice = 'chaufa' then v_item.id else null end, v_label, null, 0, 1);

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'label', v_label);
end;
$$;

-- El cliente cancela su pedido mientras siga esperando pago (o su regalo si aún no se entregó)
create or replace function public.cancel_my_food_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_order public.food_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  select * into v_order from food_orders where id = p_order_id and user_id = auth.uid() for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if not (v_order.status = 'pending' or (v_order.is_reward and v_order.status = 'paid')) then
    raise exception 'Este pedido ya no se puede cancelar desde aquí. Escríbenos por WhatsApp.';
  end if;
  update food_orders set status = 'cancelled' where id = v_order.id;
end;
$$;

-- ADMIN: cambiar el estado de un pedido
create or replace function public.admin_set_food_order_status(p_order_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare v_order public.food_orders%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_status not in ('pending', 'paid', 'delivered', 'cancelled') then raise exception 'Estado inválido'; end if;

  select * into v_order from food_orders where id = p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if v_order.status = p_status then return; end if;
  if v_order.status = 'cancelled' then
    raise exception 'Un pedido cancelado no se puede reactivar. Pide al cliente que haga uno nuevo.';
  end if;

  if p_status = 'cancelled' then
    update food_orders set status = 'cancelled' where id = v_order.id;
  elsif p_status = 'paid' then
    update food_orders set status = 'paid', paid_at = coalesce(paid_at, now()), delivered_at = null
     where id = v_order.id;
  elsif p_status = 'delivered' then
    update food_orders set status = 'delivered', paid_at = coalesce(paid_at, now()), delivered_at = now()
     where id = v_order.id;
  else
    update food_orders set status = 'pending', paid_at = null, delivered_at = null where id = v_order.id;
  end if;
end;
$$;

revoke execute on function public.food_points(uuid) from public, anon, authenticated;
revoke execute on function public.food_card() from public, anon;
revoke execute on function public.create_food_order(jsonb, text, text, text) from public, anon;
revoke execute on function public.create_food_reward(text, uuid, text, text, text) from public, anon;
revoke execute on function public.cancel_my_food_order(uuid) from public, anon;
revoke execute on function public.admin_set_food_order_status(uuid, text) from public, anon;
grant execute on function public.food_card() to authenticated;
grant execute on function public.create_food_order(jsonb, text, text, text) to authenticated;
grant execute on function public.create_food_reward(text, uuid, text, text, text) to authenticated;
grant execute on function public.cancel_my_food_order(uuid) to authenticated;
grant execute on function public.admin_set_food_order_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. CARTA INICIAL (solo si aún no hay nada)
-- ---------------------------------------------------------------------
insert into public.food_items (name, price, sort)
select * from (values
  ('Pecho',       15.00::numeric, 1),
  ('Pierna',      13.00::numeric, 2),
  ('Entrepierna', 13.00::numeric, 3),
  ('Ala',         11.00::numeric, 4)
) as v(name, price, sort)
where not exists (select 1 from public.food_items);


-- =====================================================================
--  GEKKO FOOD: fotos de las piezas del menú
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez. Las fotos se guardan en el mismo
--  bucket de Gekko (raffle-images, carpeta comida/), que ya acepta fotos
--  solo del admin.
-- =====================================================================
alter table public.food_items add column if not exists image_url text;


-- =====================================================================
--  GEKKO FOOD: nuevo acompañamiento
--    - "papa_arroz" = papa y arroz (la opción de siempre, viene marcada)
--    - "arroz"      = solo arroz
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez. Los pedidos viejos con "papa"
--  (papa sola) se siguen viendo bien, pero ya no se pueden pedir.
-- =====================================================================

alter table public.food_order_items drop constraint if exists food_order_items_side_check;
alter table public.food_order_items
  add constraint food_order_items_side_check check (side in ('papa', 'papa_arroz', 'arroz'));

-- Hacer un pedido. p_items = [{"item_id": "...", "qty": 2, "side": "papa_arroz"}, ...]
create or replace function public.create_food_order(p_items jsonb, p_name text, p_address text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.food_orders%rowtype;
  v_e       jsonb;
  v_item    public.food_items%rowtype;
  v_qty     int;
  v_side    text;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe dónde te encontramos en ESAN'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  select count(*) into v_pending from food_orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into food_orders (user_id, buyer_name, buyer_phone, address, note)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''))
  returning * into v_order;

  for v_e in select * from jsonb_array_elements(p_items) loop
    v_qty  := (v_e->>'qty')::int;
    v_side := v_e->>'side';
    if v_qty is null or v_qty < 1 or v_qty > 20 then raise exception 'Cantidad inválida'; end if;
    if v_side is null or v_side not in ('papa_arroz', 'arroz') then
      raise exception 'Elige papa y arroz, o solo arroz, en cada pieza';
    end if;

    select * into v_item from food_items where id = (v_e->>'item_id')::uuid and active;
    if not found then raise exception 'Una de las piezas ya no está disponible. Quítala del carrito.'; end if;

    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, v_item.id, v_item.name, v_side, v_item.price, v_qty);

    v_total := v_total + v_item.price * v_qty;
    v_lines := v_lines || jsonb_build_object('name', v_item.name, 'side', v_side, 'price', v_item.price, 'qty', v_qty);
  end loop;

  update food_orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total, 'items', v_lines);
end;
$$;

revoke execute on function public.create_food_order(jsonb, text, text, text) from public, anon;
grant execute on function public.create_food_order(jsonb, text, text, text) to authenticated;


-- =====================================================================
--  GEKKO FOOD: la promo del 8.º pedido
--  Con la cartilla completa (7 pedidos), el 8.º pedido se PAGA normal
--  y trae un regalo a elección:
--    - 'chaufa'      = el arroz blanco se cambia por chaufa (sin costo)
--    - 'hamburguesa' = se agrega una hamburguesa de regalo
--  El 8.º pedido no suma punto; después la cartilla vuelve a empezar.
--
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez.
--  IMPORTANTE: corre esto ANTES de que se publique el código nuevo, o el
--  botón "Ir a pagar" dará error.
-- =====================================================================

-- 1. Qué regalo eligió el cliente en su 8.º pedido
alter table public.food_orders add column if not exists reward_choice text;
alter table public.food_orders drop constraint if exists food_orders_reward_choice_check;
alter table public.food_orders
  add constraint food_orders_reward_choice_check check (reward_choice in ('chaufa', 'hamburguesa'));

-- 2. Nuevos acompañamientos: con chaufa en vez de arroz blanco
alter table public.food_order_items drop constraint if exists food_order_items_side_check;
alter table public.food_order_items
  add constraint food_order_items_side_check
  check (side in ('papa', 'papa_arroz', 'arroz', 'papa_chaufa', 'chaufa'));

-- 3. Ya no hay pedido de regalo aparte: se borra esa función
drop function if exists public.create_food_reward(text, uuid, text, text, text);

-- 4. Hacer un pedido. Ahora acepta p_reward ('chaufa' o 'hamburguesa') si la cartilla está completa.
drop function if exists public.create_food_order(jsonb, text, text, text);

create or replace function public.create_food_order(
  p_items jsonb, p_name text, p_address text, p_note text, p_reward text default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.food_orders%rowtype;
  v_e       jsonb;
  v_item    public.food_items%rowtype;
  v_qty     int;
  v_side    text;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe dónde te encontramos en ESAN'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;
  if p_reward is not null and p_reward not in ('chaufa', 'hamburguesa') then
    raise exception 'Elige tu regalo: chaufa o hamburguesa';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  if p_reward is not null and public.food_points(auth.uid()) < 7 then
    raise exception 'Aún no completas tu cartilla de 7 pedidos.';
  end if;

  select count(*) into v_pending from food_orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into food_orders (user_id, buyer_name, buyer_phone, address, note, is_reward, reward_choice)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''),
          p_reward is not null, p_reward)
  returning * into v_order;

  for v_e in select * from jsonb_array_elements(p_items) loop
    v_qty  := (v_e->>'qty')::int;
    v_side := v_e->>'side';
    if v_qty is null or v_qty < 1 or v_qty > 20 then raise exception 'Cantidad inválida'; end if;
    if v_side is null or v_side not in ('papa_arroz', 'arroz') then
      raise exception 'Elige papa y arroz, o solo arroz, en cada pieza';
    end if;

    select * into v_item from food_items where id = (v_e->>'item_id')::uuid and active;
    if not found then raise exception 'Una de las piezas ya no está disponible. Quítala del carrito.'; end if;

    -- Regalo "chaufa": el arroz blanco se cambia por chaufa, sin costo
    if p_reward = 'chaufa' then
      v_side := case v_side when 'papa_arroz' then 'papa_chaufa' else 'chaufa' end;
    end if;

    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, v_item.id, v_item.name, v_side, v_item.price, v_qty);

    v_total := v_total + v_item.price * v_qty;
    v_lines := v_lines || jsonb_build_object('name', v_item.name, 'side', v_side, 'price', v_item.price, 'qty', v_qty);
  end loop;

  -- Regalo "hamburguesa": una hamburguesa sin costo
  if p_reward = 'hamburguesa' then
    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, null, 'Hamburguesa (regalo)', null, 0, 1);
    v_lines := v_lines || jsonb_build_object('name', 'Hamburguesa (regalo)', 'side', null, 'price', 0, 'qty', 1);
  end if;

  update food_orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total,
                            'items', v_lines, 'reward', p_reward);
end;
$$;

-- 5. El cliente solo puede cancelar mientras el pedido espera pago
create or replace function public.cancel_my_food_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_order public.food_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  select * into v_order from food_orders where id = p_order_id and user_id = auth.uid() for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if v_order.status <> 'pending' then
    raise exception 'Este pedido ya no se puede cancelar desde aquí. Escríbenos por WhatsApp.';
  end if;
  update food_orders set status = 'cancelled' where id = v_order.id;
end;
$$;

revoke execute on function public.create_food_order(jsonb, text, text, text, text) from public, anon;
grant execute on function public.create_food_order(jsonb, text, text, text, text) to authenticated;
revoke execute on function public.cancel_my_food_order(uuid) from public, anon;
grant execute on function public.cancel_my_food_order(uuid) to authenticated;


-- =====================================================================
--  GEKKO FOOD: la cartilla cuenta PIEZAS, no pedidos
--  - Cada pieza pagada llena una bolita (3 pechos = 3 bolitas).
--  - La cartilla se llena con 7 y NO pasa de 7: si pides 10 piezas,
--    se llena y las 3 de más no se guardan.
--  - Después de usar la promo, la cartilla vuelve a 0 y cuentan solo
--    las piezas de los pedidos hechos después.
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez.
-- =====================================================================

create or replace function public.food_points(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
  with last_reward as (
    select max(created_at) as at
      from food_orders
     where user_id = p_user and is_reward and status <> 'cancelled'
  )
  select least(7, coalesce(sum(i.qty), 0))::int
    from food_orders o
    join food_order_items i on i.order_id = o.id
   where o.user_id = p_user
     and not o.is_reward
     and o.status in ('paid', 'delivered')
     and o.created_at > coalesce((select at from last_reward), '-infinity'::timestamptz);
$$;

revoke execute on function public.food_points(uuid) from public, anon, authenticated;


-- =====================================================================
--  GEKKO FOOD: la promo "chaufa" es SOLO para 1 pieza
--  Con la cartilla llena, si eligen chaufa, solo UNA pieza del pedido
--  (la primera del carrito) lleva chaufa en vez de arroz blanco.
--  Las demás piezas van normal.
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez.
-- =====================================================================

create or replace function public.create_food_order(
  p_items jsonb, p_name text, p_address text, p_note text, p_reward text default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.food_orders%rowtype;
  v_e       jsonb;
  v_item    public.food_items%rowtype;
  v_qty     int;
  v_side    text;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
  v_chaufa_done boolean := false;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe dónde te encontramos en ESAN'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;
  if p_reward is not null and p_reward not in ('chaufa', 'hamburguesa') then
    raise exception 'Elige tu regalo: chaufa o hamburguesa';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  if p_reward is not null and public.food_points(auth.uid()) < 7 then
    raise exception 'Aún no completas tu cartilla de 7 pedidos.';
  end if;

  select count(*) into v_pending from food_orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into food_orders (user_id, buyer_name, buyer_phone, address, note, is_reward, reward_choice)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''),
          p_reward is not null, p_reward)
  returning * into v_order;

  for v_e in select * from jsonb_array_elements(p_items) loop
    v_qty  := (v_e->>'qty')::int;
    v_side := v_e->>'side';
    if v_qty is null or v_qty < 1 or v_qty > 20 then raise exception 'Cantidad inválida'; end if;
    if v_side is null or v_side not in ('papa_arroz', 'arroz') then
      raise exception 'Elige papa y arroz, o solo arroz, en cada pieza';
    end if;

    select * into v_item from food_items where id = (v_e->>'item_id')::uuid and active;
    if not found then raise exception 'Una de las piezas ya no está disponible. Quítala del carrito.'; end if;

    -- Regalo "chaufa": SOLO 1 pieza del pedido (la primera) lleva chaufa en vez de arroz blanco, sin costo
    if p_reward = 'chaufa' and not v_chaufa_done then
      insert into food_order_items (order_id, item_id, name, side, price, qty)
      values (v_order.id, v_item.id, v_item.name,
              case v_side when 'papa_arroz' then 'papa_chaufa' else 'chaufa' end, v_item.price, 1);
      v_lines := v_lines || jsonb_build_object('name', v_item.name,
              'side', case v_side when 'papa_arroz' then 'papa_chaufa' else 'chaufa' end, 'price', v_item.price, 'qty', 1);
      v_chaufa_done := true;
      if v_qty > 1 then
        insert into food_order_items (order_id, item_id, name, side, price, qty)
        values (v_order.id, v_item.id, v_item.name, v_side, v_item.price, v_qty - 1);
        v_lines := v_lines || jsonb_build_object('name', v_item.name, 'side', v_side, 'price', v_item.price, 'qty', v_qty - 1);
      end if;
      v_total := v_total + v_item.price * v_qty;
      continue;
    end if;

    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, v_item.id, v_item.name, v_side, v_item.price, v_qty);

    v_total := v_total + v_item.price * v_qty;
    v_lines := v_lines || jsonb_build_object('name', v_item.name, 'side', v_side, 'price', v_item.price, 'qty', v_qty);
  end loop;

  -- Regalo "hamburguesa": una hamburguesa sin costo
  if p_reward = 'hamburguesa' then
    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, null, 'Hamburguesa (regalo)', null, 0, 1);
    v_lines := v_lines || jsonb_build_object('name', 'Hamburguesa (regalo)', 'side', null, 'price', 0, 'qty', 1);
  end if;

  update food_orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total,
                            'items', v_lines, 'reward', p_reward);
end;
$$;

revoke execute on function public.create_food_order(jsonb, text, text, text, text) from public, anon;
grant execute on function public.create_food_order(jsonb, text, text, text, text) to authenticated;


-- =====================================================================
--  GEKKO FOOD: refresco (y bebidas en general)
--  - Nueva columna food_items.kind: 'pieza' (pollo) o 'bebida'.
--  - Se agrega "Refresco" a S/ 1.00.
--  - Las bebidas no llevan papa/arroz, NO llenan la cartilla y no
--    reciben el chaufa de la promo.
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez.
-- =====================================================================

alter table public.food_items add column if not exists kind text not null default 'pieza';
alter table public.food_items drop constraint if exists food_items_kind_check;
alter table public.food_items add constraint food_items_kind_check check (kind in ('pieza', 'bebida'));

insert into public.food_items (name, price, sort, kind)
select 'Refresco', 1.00, 100, 'bebida'
where not exists (select 1 from public.food_items where kind = 'bebida');

-- La cartilla cuenta solo PIEZAS de pollo (no bebidas), con tope 7
create or replace function public.food_points(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
  with last_reward as (
    select max(created_at) as at
      from food_orders
     where user_id = p_user and is_reward and status <> 'cancelled'
  )
  select least(7, coalesce(sum(i.qty), 0))::int
    from food_orders o
    join food_order_items i on i.order_id = o.id
    left join food_items f on f.id = i.item_id
   where o.user_id = p_user
     and not o.is_reward
     and o.status in ('paid', 'delivered')
     and coalesce(f.kind, 'pieza') = 'pieza'
     and o.created_at > coalesce((select at from last_reward), '-infinity'::timestamptz);
$$;
revoke execute on function public.food_points(uuid) from public, anon, authenticated;

create or replace function public.create_food_order(
  p_items jsonb, p_name text, p_address text, p_note text, p_reward text default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_phone   text;
  v_pending int;
  v_order   public.food_orders%rowtype;
  v_e       jsonb;
  v_item    public.food_items%rowtype;
  v_qty     int;
  v_side    text;
  v_total   numeric(10,2) := 0;
  v_lines   jsonb := '[]'::jsonb;
  v_chaufa_done boolean := false;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Tu carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Demasiados productos en un solo pedido'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_name) > 60 then raise exception 'El nombre es muy largo'; end if;
  if coalesce(trim(p_address), '') = '' then raise exception 'Escribe dónde te encontramos en ESAN'; end if;
  if char_length(p_address) > 200 or char_length(coalesce(p_note, '')) > 200 then
    raise exception 'El texto es muy largo';
  end if;
  if p_reward is not null and p_reward not in ('chaufa', 'hamburguesa') then
    raise exception 'Elige tu regalo: chaufa o hamburguesa';
  end if;

  -- Bloquea al usuario mientras se procesa (evita dos pedidos a la vez)
  select phone into v_phone from profiles where id = auth.uid() for update;

  if p_reward is not null and public.food_points(auth.uid()) < 7 then
    raise exception 'Aún no completas tu cartilla de 7 pedidos.';
  end if;

  select count(*) into v_pending from food_orders where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then
    raise exception 'Ya tienes 3 pedidos esperando pago. Podrás hacer otro cuando confirmemos o canceles alguno.';
  end if;

  insert into food_orders (user_id, buyer_name, buyer_phone, address, note, is_reward, reward_choice)
  values (auth.uid(), trim(p_name), v_phone, trim(p_address), nullif(trim(coalesce(p_note, '')), ''),
          p_reward is not null, p_reward)
  returning * into v_order;

  for v_e in select * from jsonb_array_elements(p_items) loop
    v_qty  := (v_e->>'qty')::int;
    v_side := v_e->>'side';
    if v_qty is null or v_qty < 1 or v_qty > 20 then raise exception 'Cantidad inválida'; end if;
    select * into v_item from food_items where id = (v_e->>'item_id')::uuid and active;
    if not found then raise exception 'Uno de los productos ya no está disponible. Quítalo del carrito.'; end if;

    -- Las bebidas (refresco) no llevan acompañamiento
    if v_item.kind = 'bebida' then
      v_side := null;
    elsif v_side is null or v_side not in ('papa_arroz', 'arroz') then
      raise exception 'Elige papa y arroz, o solo arroz, en cada pieza';
    end if;

    -- Regalo "chaufa": SOLO 1 pieza del pedido (la primera) lleva chaufa en vez de arroz blanco, sin costo
    if p_reward = 'chaufa' and not v_chaufa_done and v_item.kind = 'pieza' then
      insert into food_order_items (order_id, item_id, name, side, price, qty)
      values (v_order.id, v_item.id, v_item.name,
              case v_side when 'papa_arroz' then 'papa_chaufa' else 'chaufa' end, v_item.price, 1);
      v_lines := v_lines || jsonb_build_object('name', v_item.name,
              'side', case v_side when 'papa_arroz' then 'papa_chaufa' else 'chaufa' end, 'price', v_item.price, 'qty', 1);
      v_chaufa_done := true;
      if v_qty > 1 then
        insert into food_order_items (order_id, item_id, name, side, price, qty)
        values (v_order.id, v_item.id, v_item.name, v_side, v_item.price, v_qty - 1);
        v_lines := v_lines || jsonb_build_object('name', v_item.name, 'side', v_side, 'price', v_item.price, 'qty', v_qty - 1);
      end if;
      v_total := v_total + v_item.price * v_qty;
      continue;
    end if;

    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, v_item.id, v_item.name, v_side, v_item.price, v_qty);

    v_total := v_total + v_item.price * v_qty;
    v_lines := v_lines || jsonb_build_object('name', v_item.name, 'side', v_side, 'price', v_item.price, 'qty', v_qty);
  end loop;

  if p_reward = 'chaufa' and not v_chaufa_done then
    raise exception 'Para la promo de chaufa agrega al menos una pieza de pollo';
  end if;

  -- Regalo "hamburguesa": una hamburguesa sin costo
  if p_reward = 'hamburguesa' then
    insert into food_order_items (order_id, item_id, name, side, price, qty)
    values (v_order.id, null, 'Hamburguesa (regalo)', null, 0, 1);
    v_lines := v_lines || jsonb_build_object('name', 'Hamburguesa (regalo)', 'side', null, 'price', 0, 'qty', 1);
  end if;

  update food_orders set total = v_total where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_no', v_order.order_no, 'total', v_total,
                            'items', v_lines, 'reward', p_reward);
end;
$$;

revoke execute on function public.create_food_order(jsonb, text, text, text, text) from public, anon;
grant execute on function public.create_food_order(jsonb, text, text, text, text) to authenticated;
