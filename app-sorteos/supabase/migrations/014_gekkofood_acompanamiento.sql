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
