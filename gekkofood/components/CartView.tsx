"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useCart } from "@/components/CartProvider";
import LateOrderModal from "@/components/LateOrderModal";
import SafeImg from "@/components/SafeImg";
import { createClient } from "@/lib/supabase/client";
import { buildFoodOrderWhatsAppUrl, deliveryLine, lateNotice, MAX_QTY, nextDelivery, sideLabel, type FoodItem, type Side } from "@/lib/food";
import { money, plural, YAPE_NAME, YAPE_NUMBER } from "@/lib/utils";

type Done = {
  orderNo: number;
  total: number;
  items: { name: string; side: Side; price: number; qty: number }[];
  name: string;
  phone: string;
  address: string;
  note: string | null;
  forDay: string;
  deliveryText: string;
};

export default function CartView({ items, phone }: { items: FoodItem[]; phone: string }) {
  const { lines, ready, setQty, remove, clear } = useCart();
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState<Done | null>(null);
  const [when, setWhen] = useState("Entrega de 12:30 a 2 p. m. en la Universidad ESAN (reserva hasta las 10 a. m.).");
  const [notice, setNotice] = useState<{ title: string; body: string } | null>(null);
  const [late, setLate] = useState(false); // true = el pedido ya no sale hoy

  useEffect(() => {
    setWhen(deliveryLine());
    setLate(nextDelivery().offset > 0);
  }, []);

  const byId = new Map(items.map((i) => [i.id, i]));
  const valid = lines.filter((l) => byId.has(l.itemId));
  const removed = lines.length - valid.length;
  const total = valid.reduce((a, l) => a + (byId.get(l.itemId)?.price ?? 0) * l.qty, 0);

  // Piezas que ya no están en la carta se quitan solas del carrito
  useEffect(() => {
    if (!ready) return;
    lines.filter((l) => !byId.has(l.itemId)).forEach((l) => remove(l.itemId, l.side));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, lines.length]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (valid.length === 0) return setError("Tu carrito está vacío.");
    if (!name.trim()) return setError("Escribe tu nombre.");
    if (!address.trim()) return setError("Escribe dónde te encontramos en ESAN.");

    // Si el pedido ya no sale hoy, primero hay que aceptar el aviso
    const n = lateNotice();
    if (n) return setNotice(n);
    await place();
  }

  async function place() {
    setError(null);
    setLoading(true);
    // Se abre una pestaña YA (con el toque del botón) para que el navegador no bloquee WhatsApp;
    // cuando el pedido se guarda, esa pestaña se manda a WhatsApp.
    const popup = window.open("about:blank", "_blank");
    const supabase = createClient();
    const { data, error } = await supabase.rpc("create_food_order", {
      p_items: valid.map((l) => ({ item_id: l.itemId, qty: l.qty, side: l.side })),
      p_name: name.trim(),
      p_address: address.trim(),
      p_note: note.trim(),
    });
    setLoading(false);
    if (error) {
      popup?.close();
      return setError(error.message);
    }

    const res = data as {
      order_no: number;
      total: number;
      items: { name: string; side: Side; price: number; qty: number }[];
    };
    const result: Done = {
      orderNo: res.order_no,
      total: Number(res.total),
      items: res.items.map((i) => ({ ...i, price: Number(i.price) })),
      name: name.trim(),
      phone,
      address: address.trim(),
      note: note.trim() || null,
      forDay: nextDelivery().label,
      deliveryText: deliveryLine(),
    };
    clear();
    setDone(result);

    const url = buildFoodOrderWhatsAppUrl(result);
    if (popup && !popup.closed) popup.location.href = url;
    else window.location.href = url; // si el navegador no dejó abrir otra pestaña, se va directo
  }

  if (done) {
    const url = buildFoodOrderWhatsAppUrl({
      orderNo: done.orderNo,
      name: done.name,
      phone: done.phone,
      address: done.address,
      note: done.note,
      items: done.items,
      total: done.total,
    });
    return (
      <div className="card mx-auto max-w-md p-6 text-center anim-modal">
        <p className="text-5xl">✅</p>
        <h1 className="mt-2 text-2xl font-extrabold">¡Pedido N.º {done.orderNo} enviado!</h1>
        <p className="mt-2 text-sm text-ink/70">
          Yapea <b>{money(done.total)}</b>
          {YAPE_NUMBER ? (
            <>
              {" "}
              al <b>{YAPE_NUMBER}</b>
              {YAPE_NAME ? ` (${YAPE_NAME})` : ""}
            </>
          ) : null}{" "}
          y envíanos la captura por WhatsApp para confirmar tu pedido. Ya te abrimos WhatsApp con tu pedido escrito.
        </p>
        <p className="mt-3 rounded-xl bg-gold-soft p-3 text-sm font-semibold text-ink">🕐 {done.deliveryText}</p>
        <a href={url} target="_blank" rel="noopener noreferrer" className="btn btn-green mt-5 inline-block w-full">
          Abrir WhatsApp de nuevo
        </a>
        <Link href="/mis-pedidos" className="btn btn-light mt-3 inline-block w-full">
          Ver mis pedidos
        </Link>
      </div>
    );
  }

  if (!ready) return <div className="skeleton mx-auto h-40 max-w-xl rounded-2xl" />;

  if (valid.length === 0) {
    return (
      <div className="card mx-auto max-w-md p-8 text-center">
        <p className="text-4xl">🍗</p>
        <h1 className="mt-2 text-xl font-extrabold">Tu carrito está vacío</h1>
        <p className="mt-1 text-sm text-ink/60">Elige tu pieza favorita y su acompañamiento.</p>
        <Link href="/menu" className="btn btn-primary mt-5 inline-block">
          Ver el menú
        </Link>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="mx-auto grid max-w-4xl gap-6 md:grid-cols-[1.2fr_1fr]">
      {notice && (
        <LateOrderModal
          title={notice.title}
          body={notice.body}
          onCancel={() => setNotice(null)}
          onAccept={() => {
            setNotice(null);
            void place();
          }}
        />
      )}
      <section className="space-y-3">
        <h1 className="font-display text-3xl font-semibold text-white">Tu carrito</h1>
        {removed > 0 && (
          <p className="rounded-xl bg-yellow-100 p-3 text-sm text-yellow-800">
            Quitamos del carrito algo que ya no está disponible.
          </p>
        )}
        {valid.map((l) => {
          const it = byId.get(l.itemId)!;
          return (
            <div key={l.itemId + l.side} className="card flex items-center justify-between gap-3 p-4">
              <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gold-soft">
                <SafeImg src={it.image_url} alt={it.name} icon="🍗" iconClassName="text-2xl" className="h-full w-full object-cover" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="font-extrabold [overflow-wrap:anywhere]">{it.name}</p>
                <p className="text-sm text-ink/60">{sideLabel(l.side)}</p>
                <p className="text-sm font-bold text-violet-700">{money(it.price * l.qty)}</p>
              </div>
              <div className="flex items-center gap-1 rounded-full bg-paper p-1">
                <button
                  type="button"
                  aria-label="Quitar uno"
                  onClick={() => setQty(l.itemId, l.side, l.qty - 1)}
                  className="h-9 w-9 rounded-full bg-white text-lg font-bold"
                >
                  −
                </button>
                <span className="w-7 text-center font-bold">{l.qty}</span>
                <button
                  type="button"
                  aria-label="Agregar uno"
                  disabled={l.qty >= MAX_QTY}
                  onClick={() => setQty(l.itemId, l.side, l.qty + 1)}
                  className="h-9 w-9 rounded-full bg-brand text-lg font-bold text-gold disabled:opacity-40"
                >
                  +
                </button>
              </div>
            </div>
          );
        })}
        <Link href="/menu" className="inline-block text-sm font-semibold text-gold underline underline-offset-4">
          ← Seguir pidiendo
        </Link>
      </section>

      <section className="card h-fit space-y-4 p-5">
        <div>
          <label className="mb-1 block text-sm font-medium">Tu nombre</label>
          <input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} required />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium">¿Dónde te encontramos en ESAN?</label>
          <input
            className="input"
            value={address}
            onChange={(e) => setAddress(e.target.value)}
            maxLength={200}
            placeholder="Ej: entrada principal, aula, pabellón"
            required
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium">Nota (opcional)</label>
          <input className="input" value={note} onChange={(e) => setNote(e.target.value)} maxLength={200} placeholder="Ej: sin ají" />
        </div>

        <p
          className={`rounded-xl p-3 text-sm ${
            late ? "border border-gold bg-gold-soft font-semibold text-ink" : "bg-paper text-ink/70"
          }`}
        >
          🕐 {when}
        </p>

        <div className="rounded-xl bg-paper p-4 text-sm">
          <div className="flex justify-between">
            <span>{plural(valid.reduce((a, l) => a + l.qty, 0), "producto", "productos")}</span>
            <span className="text-xl font-extrabold">{money(total)}</span>
          </div>
          <p className="mt-2 text-ink/70">
            Paga con Yape
            {YAPE_NUMBER ? (
              <>
                {" "}
                al <b>{YAPE_NUMBER}</b>
                {YAPE_NAME ? ` (${YAPE_NAME})` : ""}
              </>
            ) : null}
            . Después de pedir te mostramos cómo enviar la captura.
          </p>
        </div>

        {error && <p className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}
        <button className="btn btn-gold w-full" disabled={loading}>
          {loading ? "Enviando..." : "Ir a pagar 📲"}
        </button>
      </section>
    </form>
  );
}
