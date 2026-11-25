"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { foodStatusWhatsAppUrl, isPromoLine, REWARD_TEXT, saucesText, SAUCES, sideLabel, statusChip, type FoodOrder, type FoodStatus } from "@/lib/food";
import { formatDate, money, num, plural } from "@/lib/utils";

/** "2026-11-25" según la hora de Lima */
function limaDay(iso: string) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date(iso));
}

/** "martes 25 de noviembre" (o "hoy" / "ayer") */
function dayTitle(day: string) {
  const today = limaDay(new Date().toISOString());
  const yesterday = limaDay(new Date(Date.now() - 86_400_000).toISOString());
  const nice = new Intl.DateTimeFormat("es-PE", {
    timeZone: "UTC",
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(new Date(`${day}T12:00:00Z`));
  if (day === today) return `hoy, ${nice}`;
  if (day === yesterday) return `ayer, ${nice}`;
  return nice;
}

type Tab = "pending" | "paid" | "delivered" | "cancelled";
const TABS: { key: Tab; label: string }[] = [
  { key: "pending", label: "Por cobrar" },
  { key: "paid", label: "Por entregar" },
  { key: "delivered", label: "Entregados" },
  { key: "cancelled", label: "Cancelados" },
];

function OrderRow({ o, onHide }: { o: FoodOrder; onHide: (ids: string[], what: string) => void }) {
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
    items: o.food_order_items,
    total: o.total,
  });

  return (
    <article className={`card p-5 ${o.reward_choice ? "ring-2 ring-gold" : ""}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-extrabold">
            Pedido N.º {o.order_no}
            {saucesText(o.sauces) && <p className="mt-2 text-sm">🥫 Cremas: {saucesText(o.sauces)}</p>}
      {o.reward_choice && (
              <span className="ml-2 inline-block rounded-full bg-brand px-2.5 py-0.5 align-middle text-[0.7rem] font-bold uppercase tracking-wider text-gold">
                🎁 Promo
              </span>
            )} · <span className="[overflow-wrap:anywhere]">{o.buyer_name}</span>
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
        {(o.status === "delivered" || o.status === "cancelled") && (
          <button className="btn btn-light text-red-700" disabled={busy} onClick={() => onHide([o.id], "este pedido")}>
            🗑 Borrar
          </button>
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
  const canDelete = tab === "delivered" || tab === "cancelled";
  const router = useRouter();
  const [hiding, setHiding] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  // Pedidos agrupados por día (hora de Lima), del más reciente al más antiguo
  const days = useMemo(() => {
    const map = new Map<string, FoodOrder[]>();
    shown.forEach((o) => {
      const k = limaDay(o.created_at);
      map.set(k, [...(map.get(k) ?? []), o]);
    });
    return [...map.entries()];
  }, [shown]);

  async function hide(ids: string[], what: string, strong = false) {
    setMsg(null);
    if (strong) {
      const t = window.prompt(`Vas a borrar ${what} (${ids.length}). Escribe BORRAR para confirmar:`);
      if (t?.trim().toUpperCase() !== "BORRAR") return;
    } else if (!window.confirm(`¿Borrar ${what}? (${plural(ids.length, "pedido", "pedidos")})`)) {
      return;
    }
    setHiding(true);
    const { data, error } = await createClient().rpc("admin_hide_food_orders", { p_ids: ids });
    setHiding(false);
    if (error) return setMsg(error.message);
    setMsg(`Listo: ${plural(Number(data ?? 0), "pedido borrado", "pedidos borrados")}.`);
    router.refresh();
  }

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
    orders
      .filter((o) => o.status === "paid" && o.sauces)
      .forEach((o) =>
        SAUCES.forEach((x) => {
          const n = o.sauces?.[x.key] ?? 0;
          if (n > 0) map.set(`🥫 ${x.label}`, (map.get(`🥫 ${x.label}`) ?? 0) + n);
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

      {canDelete && shown.length > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white/5 p-3 text-sm text-white/70">
          <span>Borrar solo los quita de esta lista. La cartilla de los clientes no cambia.</span>
          <button
            className="btn btn-danger"
            disabled={hiding}
            onClick={() => hide(shown.map((o) => o.id), `TODOS los ${TABS.find((t) => t.key === tab)?.label.toLowerCase()}`, true)}
          >
            🗑 Borrar todo
          </button>
        </div>
      )}
      {msg && <p className="rounded-xl bg-white/10 p-3 text-sm text-white">{msg}</p>}

      {shown.length === 0 ? (
        <p className="text-center text-sm text-white/60">No hay pedidos aquí.</p>
      ) : (
        days.map(([day, list]) => (
          <section key={day} className="space-y-3">
            <div className="sticky top-16 z-10 flex flex-wrap items-center justify-between gap-2 rounded-xl bg-brand/95 px-3 py-2 backdrop-blur">
              <h2 className="font-display text-xl font-semibold capitalize text-gold">
                {dayTitle(day)} <span className="text-sm text-white/50">· {plural(list.length, "pedido", "pedidos")}</span>
              </h2>
              {canDelete && (
                <button
                  className="rounded-lg bg-white/10 px-3 py-1.5 text-xs font-bold text-white hover:bg-red-700"
                  disabled={hiding}
                  onClick={() => hide(list.map((o) => o.id), `los pedidos del ${dayTitle(day)}`)}
                >
                  🗑 Borrar este día
                </button>
              )}
            </div>
            {list.map((o) => (
              <OrderRow key={o.id} o={o} onHide={(ids, what) => hide(ids, what)} />
            ))}
          </section>
        ))
      )}
    </div>
  );
}
