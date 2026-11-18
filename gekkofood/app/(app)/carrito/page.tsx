import CartView from "@/components/CartView";
import type { FoodItem } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function CartPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [itemsRes, profileRes] = await Promise.all([
    supabase.from("food_items").select("id, name, price, active, sort").eq("active", true).order("sort"),
    supabase.from("profiles").select("phone").eq("id", user?.id ?? "").maybeSingle(),
  ]);
  const items = ((itemsRes.data ?? []) as FoodItem[]).map((i) => ({ ...i, price: Number(i.price) }));
  const phone = (profileRes.data as { phone?: string } | null)?.phone ?? "";
  return <CartView items={items} phone={phone} />;
}
