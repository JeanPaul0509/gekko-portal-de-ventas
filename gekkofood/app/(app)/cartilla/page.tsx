import LoyaltyCard from "@/components/LoyaltyCard";
import Link from "next/link";
import { EMPTY_CARD, type FoodCard } from "@/lib/food";
import { createClient } from "@/lib/supabase/server";

export default async function CardPage() {
  const supabase = await createClient();
  const cardRes = await supabase.rpc("food_card");
  const card = (cardRes.data as FoodCard | null) ?? EMPTY_CARD;

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
        <div className="card space-y-3 p-5 text-center">
          <p className="text-3xl">🎁</p>
          <p className="font-extrabold">Tu próximo pedido tiene promo</p>
          <p className="text-sm text-ink/70">
            Haz tu pedido normal y págalo. Al ir al carrito eliges tu regalo: cambiar el arroz blanco por chaufa o una
            hamburguesa.
          </p>
          <Link href="/menu" className="btn btn-gold inline-block">
            Hacer mi pedido con promo
          </Link>
        </div>
      ) : (
        <div className="card p-5 text-sm text-ink/70">
          <p className="font-extrabold text-ink">¿Cómo funciona?</p>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            <li>Cada pieza de pollo pagada llena una bolita: si pides 3 pechos, llenas 3. El refresco no suma.</li>
            <li>La cartilla se llena con 7. Si pides más, se llena igual y no guarda las de más.</li>
            <li>Con la cartilla llena, en tu siguiente pedido (lo pagas normal) pides chaufa en vez del arroz blanco, o una hamburguesa de regalo.</li>
            <li>El pedido con la promo no suma. Desde el siguiente, la cartilla empieza de nuevo.</li>
          </ul>
        </div>
      )}
    </div>
  );
}
