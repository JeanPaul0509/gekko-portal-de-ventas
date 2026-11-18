-- =====================================================================
--  GEKKO FOOD: fotos de las piezas del menú
--  Cómo usarlo: Supabase > SQL Editor > New query > pega TODO esto > Run
--  Es seguro correrlo más de una vez. Las fotos se guardan en el mismo
--  bucket de Gekko (raffle-images, carpeta comida/), que ya acepta fotos
--  solo del admin.
-- =====================================================================
alter table public.food_items add column if not exists image_url text;
