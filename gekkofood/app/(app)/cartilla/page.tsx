import LoyaltyCard from "@/components/LoyaltyCard";
import RewardForm from "@/components/RewardForm";
import { EMPTY_CARD, type FoodCard, type FoodItem } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function CardPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [cardRes, itemsRes, profileRes] = await Promise.all([
    supabase.rpc("food_card"),
    supabase.from("food_items").select("id, name, price, active, sort").eq("active", true).order("sort"),
    supabase.from("profiles").select("phone").eq("id", user?.id ?? "").maybeSingle(),
  ]);
  const card = (cardRes.data as FoodCard | null) ?? EMPTY_CARD;
  const items = ((itemsRes.data ?? []) as FoodItem[]).map((i) => ({ ...i, price: Number(i.price) }));
  const phone = (profileRes.data as { phone?: string } | null)?.phone ?? "";

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <header className="text-center">
        <p className="eyebrow">Gekko Food</p>
        <h1 className="font-display mt-2 text-4xl font-semibold text-white">Tu cartilla de regalo</h1>
        <hr className="gold-rule-center mx-auto my-4 max-w-xs" />
      </header>

      {cardRes.error && (
        <p className="rounded-xl bg-red-50 p-4 text-sm text-red-700">
          No pudimos cargar tu cartilla. Si acabas de crear la página, falta correr la migración 012 en Supabase.
        </p>
      )}

      <LoyaltyCard card={card} />

      {card.reward_ready ? (
        <RewardForm items={items} phone={phone} />
      ) : (
        <div className="card p-5 text-sm text-ink/70">
          <p className="font-extrabold text-ink">¿Cómo funciona?</p>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            <li>Cada pedido pagado llena una bolita.</li>
            <li>Con 7 bolitas, tu siguiente pedido es un regalo: una pieza de broaster con chaufa o una hamburguesa.</li>
            <li>El pedido de regalo no suma punto. Desde el siguiente, la cartilla empieza de nuevo.</li>
          </ul>
        </div>
      )}
    </div>
  );
}
