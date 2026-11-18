import Link from "next/link";
import type { FoodCard } from "@/lib/food";
import { plural } from "@/lib/utils";

/** Cartilla de puntos: una bolita por pedido y, al final, el regalo. */
export default function LoyaltyCard({ card, compact = false }: { card: FoodCard; compact?: boolean }) {
  const goal = card.goal;
  const left = Math.max(0, goal - card.points);

  return (
    <section className="card-lux p-5" aria-label="Tu cartilla de pedidos">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <p className="eyebrow text-gold-deep!">Tu cartilla</p>
          <h2 className="font-display text-[1.6rem] font-semibold leading-tight">
            {card.reward_ready ? "¡Tu regalo está listo!" : `${card.points} de ${goal} pedidos`}
          </h2>
        </div>
        {compact && (
          <Link href="/cartilla" className="text-sm font-semibold text-violet-700 underline underline-offset-4">
            {card.reward_ready ? "Canjear regalo →" : "Ver cartilla →"}
          </Link>
        )}
      </div>

      <div className="mt-4 grid grid-cols-8 gap-2 sm:gap-3" role="img" aria-label={`${card.points} de ${goal} pedidos completados`}>
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
          ? "Completaste tus pedidos. En tu siguiente pedido pide tu broaster con chaufa o una hamburguesa de regalo."
          : `Te ${left === 1 ? "falta" : "faltan"} ${plural(left, "pedido", "pedidos")} para tu regalo: broaster con chaufa o hamburguesa.`}
      </p>
      {!compact && (
        <p className="mt-2 text-xs text-ink/50">
          Cada pedido pagado llena una bolita. El pedido de regalo no suma punto; desde el siguiente, la cartilla empieza de nuevo.
        </p>
      )}
    </section>
  );
}
