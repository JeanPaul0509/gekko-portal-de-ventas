import Link from "next/link";
import type { FoodCard } from "@/lib/food";
import { plural } from "@/lib/utils";

/** Cartilla de puntos: una bolita por pieza y, al final, el regalo. */
export default function LoyaltyCard({ card, compact = false }: { card: FoodCard; compact?: boolean }) {
  const goal = card.goal;
  const left = Math.max(0, goal - card.points);

  return (
    <section className="card-lux p-5" aria-label="Tu cartilla de piezas">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <p className="eyebrow text-gold-deep!">Tu cartilla</p>
          <h2 className="font-display text-[1.6rem] font-semibold leading-tight">
            {card.reward_ready ? "¡Tu próximo pedido tiene promo!" : `${card.points} de ${goal} piezas`}
          </h2>
        </div>
        {compact && (
          <Link href="/cartilla" className="text-sm font-semibold text-violet-700 underline underline-offset-4">
            {card.reward_ready ? "Ver mi promo →" : "Ver cartilla →"}
          </Link>
        )}
      </div>

      <div className="mt-4 grid grid-cols-8 gap-2 sm:gap-3" role="img" aria-label={`${card.points} de ${goal} piezas`}>
        {Array.from({ length: goal }, (_, i) => (
          <div key={i} className={`punch ${i < card.points ? "punch-full" : "punch-empty"}`}>
            {i < card.points ? "✓" : i + 1}
          </div>
        ))}
        <div className={`punch text-xl ${card.reward_ready ? "punch-gift-ready" : "punch-gift"}`}>🎁</div>
      </div>

      <hr className="gold-rule my-4" />
      <p className="text-sm text-ink/70">
        {card.reward_ready
          ? "Completaste tu cartilla. En tu próximo pedido (lo pagas normal) pide chaufa en vez del arroz blanco, o una hamburguesa de regalo."
          : `Te ${left === 1 ? "falta" : "faltan"} ${plural(left, "pieza", "piezas")} para llenar tu cartilla. Luego, en tu siguiente pedido pides chaufa en vez del arroz blanco, o una hamburguesa de regalo.`}
      </p>
      {!compact && (
        <p className="mt-2 text-xs text-ink/50">
          Cada pieza pagada llena una bolita (3 pechos = 3 bolitas). La cartilla se llena con 7 y no guarda piezas de más. El pedido con la promo no suma; desde el siguiente, la cartilla empieza de nuevo.
        </p>
      )}
    </section>
  );
}
