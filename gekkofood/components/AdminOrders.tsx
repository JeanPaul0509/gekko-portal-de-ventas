"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { foodStatusWhatsAppUrl, sideLabel, statusChip, type FoodOrder, type FoodStatus } from "@/lib/food";
import { formatDate, money, num } from "@/lib/utils";

type Tab = "pending" | "paid" | "delivered" | "cancelled";
const TABS: { key: Tab; label: string }[] = [
  { key: "pending", label: "Por cobrar" },
  { key: "paid", label: "Por entregar" },
  { key: "delivered", label: "Entregados" },
  { key: "cancelled", label: "Cancelados" },
];

function OrderRow({ o }: { o: FoodOrder }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const chip = statusChip(o);

  async function setStatus(status: FoodStatus) {
    setBusy(true);
    setError(null);
    const { error } = await createClient().rpc("admin_set_food_order_status", { p_order_id: o.id, p_status: status });
    setBusy(false);
    if (error) return setError(error.message);
    setConfirmCancel(false);
    router.refresh();
  }

  const wa = foodStatusWhatsAppUrl({
    phone: o.buyer_phone,
    name: o.buyer_name,
    orderNo: o.order_no,
    status: o.status,
    isReward: o.is_reward,
    items: o.food_order_items,
    total: o.total,
  });

  return (
    <article className="card p-5">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-extrabold">
            {o.is_reward ? "🎁 Regalo" : "Pedido"} N.º {o.order_no} · <span className="[overflow-wrap:anywhere]">{o.buyer_name}</span>
          </p>
          <p className="text-xs text-ink/50">
            {formatDate(o.created_at)} · 📱 {o.buyer_phone}
          </p>
          {o.address && <p className="mt-1 text-sm [overflow-wrap:anywhere]">📍 {o.address}</p>}
          {o.note && <p className="text-sm [overflow-wrap:anywhere]">📝 {o.note}</p>}
        </div>
        <span className={`rounded-full px-3 py-1 text-xs font-bold ${chip.cls}`}>{chip.label}</span>
      </div>

      <ul className="mt-3 space-y-1 text-sm">
        {o.food_order_items.map((i) => (
          <li key={i.id} className="flex justify-between gap-3">
            <span className="[overflow-wrap:anywhere]">
              {i.qty} × {i.name}
              {i.side ? ` (${sideLabel(i.side)})` : ""}
            </span>
            {i.price > 0 && <span className="shrink-0 font-semibold">{money(i.price * i.qty)}</span>}
          </li>
        ))}
      </ul>
      {!o.is_reward && (
        <p className="mt-3 flex justify-between border-t border-line pt-3 font-extrabold">
          <span>Total</span>
          <span>{money(o.total)}</span>
        </p>
      )}

      {error && <p className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}

      <div className="mt-4 flex flex-wrap gap-2">
        {o.status === "pending" && (
          <button className="btn btn-green" disabled={busy} onClick={() => setStatus("paid")}>
            Confirmar pago
          </button>
        )}
        {o.status === "paid" && (
          <button className="btn btn-primary" disabled={busy} onClick={() => setStatus("delivered")}>
            Marcar entregado
          </button>
        )}
        {o.status !== "pending" && (
          <a href={wa} target="_blank" rel="noopener noreferrer" className="btn btn-light">
            Avisarle por WhatsApp
          </a>
        )}
        {(o.status === "pending" || o.status === "paid") &&
          (confirmCancel ? (
            <>
              <button className="btn btn-danger" disabled={busy} onClick={() => setStatus("cancelled")}>
                Sí, cancelar
              </button>
              <button className="btn btn-light" disabled={busy} onClick={() => setConfirmCancel(false)}>
                No
              </button>
            </>
          ) : (
            <button className="btn btn-light" disabled={busy} onClick={() => setConfirmCancel(true)}>
              Cancelar
            </button>
          ))}
      </div>
    </article>
  );
}

export default function AdminOrders({ orders }: { orders: FoodOrder[] }) {
  const [tab, setTab] = useState<Tab>("pending");
  const shown = orders.filter((o) => o.status === tab);

  // Lo que hay que preparar: suma de las piezas de los pedidos pagados que faltan entregar
  const prep = useMemo(() => {
    const map = new Map<string, number>();
    orders
      .filter((o) => o.status === "paid")
      .forEach((o) =>
        o.food_order_items.forEach((i) => {
          const k = i.side ? `${i.name} (${sideLabel(i.side)})` : i.name;
          map.set(k, (map.get(k) ?? 0) + i.qty);
        })
      );
    return [...map.entries()].sort((a, b) => b[1] - a[1]);
  }, [orders]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {TABS.map((t) => {
          const count = orders.filter((o) => o.status === t.key).length;
          return (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              aria-pressed={tab === t.key}
              className={`rounded-xl px-4 py-2 text-sm font-bold ${
                tab === t.key ? "bg-gold text-ink" : "bg-white/10 text-white hover:bg-white/15"
              }`}
            >
              {t.label} ({num(count)})
            </button>
          );
        })}
      </div>

      {tab === "paid" && prep.length > 0 && (
        <div className="card p-5">
          <p className="font-extrabold">Para preparar</p>
          <ul className="mt-2 grid gap-1 text-sm sm:grid-cols-2">
            {prep.map(([name, qty]) => (
              <li key={name} className="flex justify-between gap-3 rounded-lg bg-paper px-3 py-2">
                <span className="[overflow-wrap:anywhere]">{name}</span>
                <b>{num(qty)}</b>
              </li>
            ))}
          </ul>
        </div>
      )}

      {shown.length === 0 ? (
        <p className="text-center text-sm text-white/60">No hay pedidos aquí.</p>
      ) : (
        shown.map((o) => <OrderRow key={o.id} o={o} />)
      )}
    </div>
  );
}
