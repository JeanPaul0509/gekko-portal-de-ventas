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
