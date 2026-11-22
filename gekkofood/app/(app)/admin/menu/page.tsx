import AdminMenu from "@/components/AdminMenu";
import type { FoodItem } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function AdminMenuPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.from("food_items").select("id, name, price, active, sort, image_url, kind").order("sort");
  const items = ((data ?? []) as FoodItem[]).map((i) => ({ ...i, price: Number(i.price) }));

  return (
    <div className="space-y-4">
      <h1 className="font-display text-4xl font-semibold text-white">Menú de Gekko Food</h1>
      {error ? (
        <p className="rounded-xl bg-red-50 p-4 text-sm text-red-700">No pudimos cargar el menú: {error.message}</p>
      ) : (
        <AdminMenu items={items} />
      )}
    </div>
  );
}
