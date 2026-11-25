import OrdersList from "@/components/OrdersList";
import type { FoodOrder } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function MyOrdersPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Se filtra por usuario porque el admin también puede leer los pedidos de todos
  const { data, error } = await supabase
    .from("food_orders")
    .select(
      "id, order_no, user_id, buyer_name, buyer_phone, address, note, total, is_reward, reward_choice, sauces, status, created_at, food_order_items(id, name, side, price, qty)"
    )
    .eq("user_id", user?.id ?? "")
    .order("created_at", { ascending: false })
    .limit(50);

  const orders = ((data ?? []) as unknown as FoodOrder[]).map((o) => ({
    ...o,
    total: Number(o.total),
    food_order_items: o.food_order_items.map((i) => ({ ...i, price: Number(i.price) })),
  }));

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <h1 className="font-display text-4xl font-semibold text-white">Mis pedidos</h1>
      {error ? (
        <p className="rounded-xl bg-red-50 p-4 text-sm text-red-700">
          No pudimos cargar tus pedidos. Si acabas de crear la página, falta correr la migración 012 en Supabase.
        </p>
      ) : (
        <OrdersList orders={orders} />
      )}
    </div>
  );
}
