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
