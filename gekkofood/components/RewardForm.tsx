"use client";

import Link from "next/link";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { buildRewardWhatsAppUrl, type FoodItem } from "@/lib/food";
import { money } from "@/lib/utils";

type Choice = "chaufa" | "hamburguesa";

export default function RewardForm({ items, phone }: { items: FoodItem[]; phone: string }) {
  const [choice, setChoice] = useState<Choice>("chaufa");
  const [itemId, setItemId] = useState<string>(items[0]?.id ?? "");
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState<{ orderNo: number; label: string; name: string; address: string; note: string | null } | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!name.trim()) return setError("Escribe tu nombre.");
    if (!address.trim()) return setError("Escribe dónde te encontramos en ESAN.");
    if (choice === "chaufa" && !itemId) return setError("Elige la pieza de tu broaster.");

    setLoading(true);
    const popup = window.open("about:blank", "_blank"); // se abre con el toque para que no lo bloqueen
    const { data, error } = await createClient().rpc("create_food_reward", {
      p_choice: choice,
      p_item_id: choice === "chaufa" ? itemId : null,
      p_name: name.trim(),
      p_address: address.trim(),
      p_note: note.trim(),
    });
    setLoading(false);
    if (error) {
      popup?.close();
      return setError(error.message);
    }

    const res = data as { order_no: number; label: string };
    const result = { orderNo: res.order_no, label: res.label, name: name.trim(), address: address.trim(), note: note.trim() || null };
    setDone(result);
    const url = buildRewardWhatsAppUrl({ ...result, phone });
    if (popup && !popup.closed) popup.location.href = url;
    else window.location.href = url;
  }

  if (done) {
    const url = buildRewardWhatsAppUrl({ ...done, phone });
    return (
      <div className="card p-6 text-center anim-modal">
        <p className="text-5xl">🎁</p>
        <h2 className="mt-2 text-2xl font-extrabold">¡Regalo pedido! N.º {done.orderNo}</h2>
        <p className="mt-2 text-sm text-ink/70">{done.label}. Avísanos por WhatsApp para confirmar. Entrega de 1 a 2 p. m. en la Universidad ESAN.</p>
        <a href={url} target="_blank" rel="noopener noreferrer" className="btn btn-green mt-5 inline-block w-full">
          Abrir WhatsApp de nuevo
        </a>
        <Link href="/mis-pedidos" className="btn btn-light mt-3 inline-block w-full">
          Ver mis pedidos
        </Link>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="card space-y-4 p-5">
      <div>
        <p className="eyebrow text-gold-deep!">Canjear regalo</p>
        <h2 className="font-display text-2xl font-semibold">Elige tu regalo</h2>
      </div>

      <div className="grid grid-cols-2 gap-2" role="radiogroup" aria-label="Regalo">
        {(
          [
            { key: "chaufa", label: "🍗 Broaster con chaufa" },
            { key: "hamburguesa", label: "🍔 Hamburguesa" },
          ] as { key: Choice; label: string }[]
        ).map((c) => (
          <button
            key={c.key}
            type="button"
            role="radio"
            aria-checked={choice === c.key}
            onClick={() => setChoice(c.key)}
            className={`rounded-xl border px-3 py-3 text-sm font-bold transition ${
              choice === c.key ? "border-gold bg-brand text-gold" : "border-line bg-white text-ink/70"
            }`}
          >
            {c.label}
          </button>
        ))}
      </div>

      {choice === "chaufa" && (
        <div>
          <label className="mb-1 block text-sm font-medium">¿Qué pieza quieres?</label>
          <select className="input" value={itemId} onChange={(e) => setItemId(e.target.value)}>
            {items.map((i) => (
              <option key={i.id} value={i.id}>
                {i.name} (vale {money(i.price)})
              </option>
            ))}
          </select>
        </div>
      )}

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
        <input className="input" value={note} onChange={(e) => setNote(e.target.value)} maxLength={200} />
      </div>

      {error && <p className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      <button className="btn btn-gold w-full" disabled={loading}>
        {loading ? "Enviando..." : "Canjear mi regalo 🎁"}
      </button>
      <p className="text-center text-xs text-ink/50">Este pedido no se paga y no suma punto.</p>
    </form>
  );
}
