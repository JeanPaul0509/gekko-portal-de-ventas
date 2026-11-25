import Link from "next/link";
import LoyaltyCard from "@/components/LoyaltyCard";
import MenuView from "@/components/MenuView";
import { DELIVERY_NOTE, deliveryLine, EMPTY_CARD, nextDelivery, type FoodCard, type FoodItem } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export const metadata = {
  title: "Menú · Pollo broaster en la Universidad ESAN",
  description:
    "Pecho, pierna, entrepierna y ala de pollo broaster con papa y arroz. Pide hasta las 10 a. m. y recíbelo de 12:30 a 2:00 p. m. en la Universidad ESAN. Paga con Yape.",
  alternates: { canonical: "/menu" },
};

export default async function MenuPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [itemsRes, cardRes] = await Promise.all([
    supabase.from("food_items").select("id, name, price, active, sort, image_url, kind, stock").eq("active", true).order("sort"),
    user ? supabase.rpc("food_card") : Promise.resolve({ data: null }),
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
        <p
          className={`mx-auto mt-3 max-w-md rounded-xl px-4 py-3 text-sm font-semibold ${
            nextDelivery().offset > 0 ? "border border-gold bg-gold/15 text-gold" : "text-gold"
          }`}
        >
          🕐 {deliveryLine()}
        </p>
        <p className="mt-3 text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-gold/80">
          Papa y arroz ◆ Solo arroz ◆ Paga con Yape
        </p>
      </section>

      <div className="anim-rise" style={{ ["--delay" as string]: "80ms" }}>
        {user ? (
          <LoyaltyCard card={card} compact />
        ) : (
          <section className="card-lux p-5 text-center">
            <p className="eyebrow text-gold-deep!">Cartilla de puntos</p>
            <h2 className="font-display mt-1 text-[1.6rem] font-semibold leading-tight">
              Cada pieza llena una bolita. Con 7, tu regalo.
            </h2>
            <p className="mt-2 text-sm text-ink/70">
              Para pedir, entra con tu cuenta de Gekko o crea una gratis en un minuto.
            </p>
            <div className="mt-4 flex flex-wrap justify-center gap-2">
              <Link href="/registro" className="btn btn-gold">
                Crear cuenta
              </Link>
              <Link href="/login" className="btn btn-light">
                Ya tengo cuenta
              </Link>
            </div>
          </section>
        )}
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
