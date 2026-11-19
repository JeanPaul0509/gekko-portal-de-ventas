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
