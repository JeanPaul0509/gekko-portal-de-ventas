import CartView from "@/components/CartView";
import { EMPTY_CARD, type FoodCard, type FoodItem } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function CartPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [itemsRes, profileRes, cardRes] = await Promise.all([
    supabase.from("food_items").select("id, name, price, active, sort, image_url").eq("active", true).order("sort"),
    supabase.from("profiles").select("phone").eq("id", user?.id ?? "").maybeSingle(),
    supabase.rpc("food_card"),
  ]);
  const items = ((itemsRes.data ?? []) as FoodItem[]).map((i) => ({ ...i, price: Number(i.price) }));
  const phone = (profileRes.data as { phone?: string } | null)?.phone ?? "";
  const card = (cardRes.data as FoodCard | null) ?? EMPTY_CARD;
  return <CartView items={items} phone={phone} promoReady={card.reward_ready} />;
}
