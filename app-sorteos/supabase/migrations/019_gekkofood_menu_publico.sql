-- =====================================================================
--  GEKKO FOOD: el menú se puede ver SIN iniciar sesión
--  Las personas sin cuenta (y Google) pueden ver las piezas visibles y
--  sus precios. Para pedir sigue haciendo falta iniciar sesión.
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez.
-- =====================================================================
grant select on public.food_items to anon;
drop policy if exists "ver carta publica" on public.food_items;
create policy "ver carta publica" on public.food_items
  for select to anon using (active);
