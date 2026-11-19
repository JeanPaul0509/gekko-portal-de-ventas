"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { buildFoodOrderWhatsAppUrl, isPromoLine, REWARD_TEXT, sideLabel, statusChip, type FoodOrder } from "@/lib/food";
import { formatDate, money, YAPE_NAME, YAPE_NUMBER } from "@/lib/utils";

function OrderCard({ o }: { o: FoodOrder }) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const chip = statusChip(o);
  const canCancel = o.status === "pending";

  async function cancel() {
    setBusy(true);
    setError(null);
    const { error } = await createClient().rpc("cancel_my_food_order", { p_order_id: o.id });
    setBusy(false);
    if (error) return setError(error.message);
    setConfirming(false);
    router.refresh();
  }

  const waUrl = buildFoodOrderWhatsAppUrl({
    orderNo: o.order_no,
    name: o.buyer_name,
    phone: o.buyer_phone,
    address: o.address ?? "",
    note: o.note,
    items: o.food_order_items,
    total: o.total,
    reward: o.reward_choice,
  });

  return (
    <article className={`card p-5 ${o.reward_choice ? "ring-2 ring-gold" : ""}`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="font-extrabold">
            Pedido N.º {o.order_no}
            {o.reward_choice && (
              <span className="ml-2 inline-block rounded-full bg-brand px-2.5 py-0.5 align-middle text-[0.7rem] font-bold uppercase tracking-wider text-gold">
                🎁 Promo
              </span>
            )}
          </p>
          <p className="text-xs text-ink/50">{formatDate(o.created_at)}</p>
        </div>
        <span className={`rounded-full px-3 py-1 text-xs font-bold ${chip.cls}`}>{chip.label}</span>
      </div>

      <ul className="mt-3 space-y-1 text-sm">
        {o.food_order_items.map((i) => (
          <li
            key={i.id}
            className={`flex justify-between gap-3 ${
              isPromoLine(i) ? "-mx-2 rounded-lg bg-gold-soft px-2 py-1 font-bold" : ""
            }`}
          >
            <span className="[overflow-wrap:anywhere]">
              {isPromoLine(i) && "🎁 "}
              {i.qty} × {i.name}
              {i.side ? ` (${sideLabel(i.side)})` : ""}
            </span>
            {i.price > 0 && <span className="shrink-0 font-semibold">{money(i.price * i.qty)}</span>}
          </li>
        ))}
      </ul>
      {o.reward_choice && (
        <p className="mt-3 rounded-xl border border-gold bg-brand p-3 text-sm font-bold text-gold">
          🎁 Promo cartilla llena: {REWARD_TEXT[o.reward_choice]}
        </p>
      )}
      <p className="mt-3 flex justify-between border-t border-line pt-3 font-extrabold">
        <span>Total</span>
        <span>{money(o.total)}</span>
      </p>

      {o.status === "pending" && (
        <p className="mt-3 rounded-xl bg-paper p-3 text-sm text-ink/70">
          Yapea <b>{money(o.total)}</b>
          {YAPE_NUMBER ? (
            <>
              {" "}
              al <b>{YAPE_NUMBER}</b>
              {YAPE_NAME ? ` (${YAPE_NAME})` : ""}
            </>
          ) : null}{" "}
          y envía la captura por WhatsApp.
        </p>
      )}

      {error && <p className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}

      <div className="mt-4 flex flex-wrap gap-2">
        {o.status === "pending" && (
          <a href={waUrl} target="_blank" rel="noopener noreferrer" className="btn btn-green">
            Reenviar por WhatsApp
          </a>
        )}
        {canCancel &&
          (confirming ? (
            <>
              <button className="btn btn-danger" onClick={cancel} disabled={busy}>
                {busy ? "Cancelando..." : "Sí, cancelar"}
              </button>
              <button className="btn btn-light" onClick={() => setConfirming(false)} disabled={busy}>
                No
              </button>
            </>
          ) : (
            <button className="btn btn-light" onClick={() => setConfirming(true)}>
              Cancelar pedido
            </button>
          ))}
      </div>
    </article>
  );
}

export default function OrdersList({ orders }: { orders: FoodOrder[] }) {
  if (orders.length === 0) {
    return (
      <div className="card p-8 text-center">
        <p className="text-4xl">🍗</p>
        <p className="mt-2 font-extrabold">Aún no tienes pedidos</p>
        <Link href="/menu" className="btn btn-primary mt-4 inline-block">
          Ver el menú
        </Link>
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {orders.map((o) => (
        <OrderCard key={o.id} o={o} />
      ))}
    </div>
  );
}
