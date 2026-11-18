import LoyaltyCard from "@/components/LoyaltyCard";
import MenuView from "@/components/MenuView";
import { DELIVERY_NOTE, deliveryLine, EMPTY_CARD, type FoodCard, type FoodItem } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function MenuPage() {
  const supabase = await createClient();
  const [itemsRes, cardRes] = await Promise.all([
    supabase.from("food_items").select("id, name, price, active, sort").eq("active", true).order("sort"),
    supabase.rpc("food_card"),
  ]);

  const items = ((itemsRes.data ?? []) as FoodItem[]).map((i) => ({ ...i, price: Number(i.price) }));
  const card = (cardRes.data as FoodCard | null) ?? EMPTY_CARD;

  return (
    <div className="space-y-8">
      <section className="anim-rise text-center">
        <p className="eyebrow">Pollo broaster</p>
        <h1 className="font-display mx-auto mt-2 max-w-xl text-[2.6rem] font-semibold leading-[1.04] text-white sm:text-6xl">
          Crujiente por fuera, jugoso por dentro
        </h1>
        <hr className="gold-rule-center mx-auto my-5 max-w-xs" />
        <p className="mx-auto max-w-md text-sm text-white/70">{DELIVERY_NOTE}</p>
        <p className="mx-auto mt-2 max-w-md text-sm font-semibold text-gold">{deliveryLine()}</p>
        <p className="mt-3 text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-gold/80">
          Papa sola ◆ Con arroz ◆ Paga con Yape
        </p>
      </section>

      <div className="anim-rise" style={{ ["--delay" as string]: "80ms" }}>
        <LoyaltyCard card={card} compact />
      </div>

      {itemsRes.error ? (
        <p className="rounded-xl bg-red-50 p-4 text-sm text-red-700">
          No pudimos cargar el menú. Si acabas de crear la página, falta correr la migración 012 en Supabase.
        </p>
      ) : (
        <MenuView items={items} />
      )}
    </div>
  );
}
