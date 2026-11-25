"use client";

import Link from "next/link";
import { useState } from "react";
import { useCart } from "@/components/CartProvider";
import SafeImg from "@/components/SafeImg";
import { isSoldOut, SIDES, type CartSide, type FoodItem } from "@/lib/food";
import { money, plural } from "@/lib/utils";

function ItemCard({ item }: { item: FoodItem }) {
  const { add, lines } = useCart();
  const [side, setSide] = useState<CartSide>("papa_arroz");
  const inCart = lines.filter((l) => l.itemId === item.id).reduce((a, l) => a + l.qty, 0);
  const soldOut = isSoldOut(item);

  return (
    <article className={`card-lux flex flex-col p-5 ${soldOut ? "opacity-60" : ""}`}>
      <div className="mb-4 aspect-[4/3] overflow-hidden rounded-xl bg-gold-soft">
        <SafeImg src={item.image_url} alt={item.name} icon="🍗" className="lux-img h-full w-full object-cover" />
      </div>
      <p className="eyebrow text-gold-deep!">Broaster</p>
      <h3 className="mt-1 text-xl font-extrabold [overflow-wrap:anywhere]">{item.name}</h3>
      <p className="mt-1 text-sm text-ink/60">Elige papa y arroz, o solo arroz.</p>

      <div className="mt-4 grid grid-cols-2 gap-1.5 rounded-xl bg-paper p-1" role="radiogroup" aria-label={`Acompañamiento de ${item.name}`}>
        {SIDES.map((s) => (
          <button
            key={s.key}
            type="button"
            role="radio"
            aria-checked={side === s.key}
            onClick={() => setSide(s.key)}
            className={`rounded-lg px-2 py-2 text-sm font-bold transition ${
              side === s.key ? "bg-brand text-gold" : "text-ink/60 hover:text-ink"
            }`}
          >
            {s.label}
          </button>
        ))}
      </div>

      <hr className="gold-rule my-4" />
      <div className="mt-auto flex items-center justify-between gap-3">
        <p className="text-[1.6rem] font-extrabold tracking-tight text-violet-700">{money(item.price)}</p>
        <button
          type="button"
          className="btn btn-primary"
          disabled={soldOut || (item.stock !== null && inCart >= item.stock)}
          onClick={() => add(item.id, side)}
        >
          {soldOut ? "Agotado" : "Agregar"}
        </button>
      </div>
      {inCart > 0 && <p className="mt-2 text-xs font-semibold text-gold-deep">{plural(inCart, "unidad", "unidades")} en tu carrito</p>}
      {soldOut ? (
        <p className="mt-2 text-xs font-bold text-red-700">Agotado por hoy. Vuelve pronto 🙌</p>
      ) : (
        item.stock !== null &&
        item.stock <= 5 && <p className="mt-2 text-xs font-bold text-red-700">¡Quedan {item.stock}!</p>
      )}
    </article>
  );
}

function DrinkCard({ item }: { item: FoodItem }) {
  const { add, lines } = useCart();
  const inCart = lines.filter((l) => l.itemId === item.id).reduce((a, l) => a + l.qty, 0);
  return (
    <article className="card-lux flex items-center gap-4 p-4">
      <div className="h-16 w-16 shrink-0 overflow-hidden rounded-xl bg-gold-soft">
        <SafeImg src={item.image_url} alt={item.name} icon="🥤" iconClassName="text-3xl" className="h-full w-full object-cover" />
      </div>
      <div className="min-w-0 flex-1">
        <h3 className="text-lg font-extrabold [overflow-wrap:anywhere]">{item.name}</h3>
        <p className="text-lg font-extrabold text-violet-700">{money(item.price)}</p>
        {inCart > 0 && <p className="text-xs font-semibold text-gold-deep">{plural(inCart, "unidad", "unidades")} en tu carrito</p>}
      </div>
      <button
        type="button"
        className="btn btn-primary"
        disabled={isSoldOut(item) || (item.stock !== null && inCart >= item.stock)}
        onClick={() => add(item.id, "sin")}
      >
        {isSoldOut(item) ? "Agotado" : "Agregar"}
      </button>
    </article>
  );
}

export default function MenuView({ items }: { items: FoodItem[] }) {
  const { lines, count } = useCart();
  const byId = new Map(items.map((i) => [i.id, i]));
  const total = lines.reduce((a, l) => a + (byId.get(l.itemId)?.price ?? 0) * l.qty, 0);
  const pieces = items.filter((i) => i.kind !== "bebida");
  const drinks = items.filter((i) => i.kind === "bebida");

  if (items.length === 0) {
    return <p className="text-center text-sm text-white/60">Pronto tendremos el menú disponible.</p>;
  }

  return (
    <>
      <div className="grid gap-5 sm:grid-cols-2">
        {pieces.map((it, i) => (
          <div key={it.id} className="anim-rise flex" style={{ ["--delay" as string]: `${120 + i * 60}ms` }}>
            <div className="flex w-full flex-col [&>article]:flex-1">
              <ItemCard item={it} />
            </div>
          </div>
        ))}
      </div>

      {drinks.length > 0 && (
        <section className="mt-8 space-y-3">
          <h2 className="font-display text-2xl font-semibold text-white">Bebidas</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            {drinks.map((d) => (
              <DrinkCard key={d.id} item={d} />
            ))}
          </div>
        </section>
      )}

      {count > 0 && (
        <div className="anim-sheet fixed inset-x-0 bottom-0 z-40 border-t border-gold/30 bg-white/95 backdrop-blur-md">
          <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-3 text-ink">
            <p className="text-sm font-semibold">
              {plural(count, "producto", "productos")} · <span className="text-violet-700">{money(total)}</span>
            </p>
            <Link href="/carrito" className="btn btn-primary">
              Ver carrito →
            </Link>
          </div>
        </div>
      )}
    </>
  );
}
