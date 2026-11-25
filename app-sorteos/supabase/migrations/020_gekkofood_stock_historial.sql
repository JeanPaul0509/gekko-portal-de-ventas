-- =====================================================================
--  GEKKO FOOD: unidades disponibles por producto + limpiar historial
--  1. food_items.stock: cuántas unidades quedan (vacío/null = sin límite).
--     Cada pedido descuenta; al cancelar se devuelven. En 0 = "Agotado".
--  2. food_orders.admin_hidden: el admin puede quitar pedidos ENTREGADOS o
--     CANCELADOS de su lista (uno, un día o todos). No se borran de verdad,
--     así la cartilla de puntos de los clientes no se pierde.
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez.
-- =====================================================================

alter table public.food_items add column if not exists stock int;
alter table public.food_items drop constraint if exists food_items_stock_check;
alter table public.food_items add constraint food_items_stock_check check (stock is null or stock >= 0);

alter table public.food_orders add column if not exists admin_hidden boolean not null default false;

-- Devuelve al stock las unidades de un pedido (al cancelarlo)
create or replace function public.food_restore_stock(p_order_id uuid)
returns void language sql security definer set search_path = public as $$
  update food_items f
     set stock = f.stock + s.q
    from (select item_id, sum(qty)::int as q
            from food_order_items
           where order_id = p_order_id and item_id is not null
           group by item_id) s
   where f.id = s.item_id and f.stock is not null;
$$;
revoke execute on function public.food_restore_stock(uuid) from public, anon, authenticated;

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
    select * into v_item from food_items where id = (v_e->>'item_id')::uuid and active for update;
    if not found then raise exception 'Uno de los productos ya no está disponible. Quítalo del carrito.'; end if;

    -- Unidades disponibles (null = sin límite)
    if v_item.stock is not null then
      if v_item.stock < v_qty then
        if v_item.stock = 0 then
          raise exception 'Se agotó %. Quítalo de tu carrito.', v_item.name;
        end if;
        raise exception 'Solo quedan % de %. Baja la cantidad en tu carrito.', v_item.stock, v_item.name;
      end if;
      update food_items set stock = stock - v_qty where id = v_item.id;
    end if;

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

-- El cliente cancela (solo mientras espera pago): devuelve las unidades
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
  perform public.food_restore_stock(v_order.id);
end;
$$;

-- ADMIN: cambiar estado (cancelar devuelve las unidades)
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
    perform public.food_restore_stock(v_order.id);
  elsif p_status = 'paid' then
    update food_orders set status = 'paid', paid_at = coalesce(paid_at, now()), delivered_at = null where id = v_order.id;
  elsif p_status = 'delivered' then
    update food_orders set status = 'delivered', paid_at = coalesce(paid_at, now()), delivered_at = now() where id = v_order.id;
  else
    update food_orders set status = 'pending', paid_at = null, delivered_at = null where id = v_order.id;
  end if;
end;
$$;

-- ADMIN: quitar pedidos del historial (solo entregados o cancelados). Devuelve cuántos quitó.
create or replace function public.admin_hide_food_orders(p_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  update food_orders set admin_hidden = true
   where id = any(p_ids) and status in ('delivered', 'cancelled') and not admin_hidden;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function public.create_food_order(jsonb, text, text, text, text) from public, anon;
grant execute on function public.create_food_order(jsonb, text, text, text, text) to authenticated;
revoke execute on function public.cancel_my_food_order(uuid) from public, anon;
grant execute on function public.cancel_my_food_order(uuid) to authenticated;
revoke execute on function public.admin_set_food_order_status(uuid, text) from public, anon;
grant execute on function public.admin_set_food_order_status(uuid, text) to authenticated;
revoke execute on function public.admin_hide_food_orders(uuid[]) from public, anon;
grant execute on function public.admin_hide_food_orders(uuid[]) to authenticated;
