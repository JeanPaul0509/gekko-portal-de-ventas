import AdminOrders from "@/components/AdminOrders";
import type { FoodOrder } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function AdminOrdersPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("food_orders")
    .select(
      "id, order_no, user_id, buyer_name, buyer_phone, address, note, total, is_reward, reward_choice, status, created_at, food_order_items(id, name, side, price, qty)"
    )
    .eq("admin_hidden", false)
    .order("created_at", { ascending: false })
    .limit(300);

  const orders = ((data ?? []) as unknown as FoodOrder[]).map((o) => ({
    ...o,
    total: Number(o.total),
    food_order_items: o.food_order_items.map((i) => ({ ...i, price: Number(i.price) })),
  }));

  return (
    <div className="space-y-4">
      <h1 className="font-display text-4xl font-semibold text-white">Pedidos de Gekko Food</h1>
      {error ? (
        <p className="rounded-xl bg-red-50 p-4 text-sm text-red-700">No pudimos cargar los pedidos: {error.message}</p>
      ) : (
        <AdminOrders orders={orders} />
      )}
    </div>
  );
}
