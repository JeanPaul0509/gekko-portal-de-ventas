"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { FoodItem } from "@/lib/food";

function Row({ item }: { item: FoodItem }) {
  const router = useRouter();
  const [name, setName] = useState(item.name);
  const [price, setPrice] = useState(String(item.price));
  const [active, setActive] = useState(item.active);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const p = Number(price.replace(",", "."));
  const changed = name.trim() !== item.name || p !== item.price || active !== item.active;

  async function save() {
    setMsg(null);
    if (!name.trim()) return setMsg("Escribe un nombre.");
    if (!Number.isFinite(p) || p < 0 || p > 1000) return setMsg("Precio inválido.");
    setBusy(true);
    const { error } = await createClient()
      .from("food_items")
      .update({ name: name.trim(), price: p, active })
      .eq("id", item.id);
    setBusy(false);
    if (error) return setMsg(error.message);
    setMsg("Guardado ✅");
    router.refresh();
  }

  return (
    <div className="card flex flex-wrap items-end gap-3 p-4">
      <div className="min-w-[8rem] flex-1">
        <label className="mb-1 block text-xs font-medium">Nombre</label>
        <input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} />
      </div>
      <div className="w-28">
        <label className="mb-1 block text-xs font-medium">Precio (S/)</label>
        <input className="input" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} />
      </div>
      <label className="flex items-center gap-2 pb-3 text-sm font-semibold">
        <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
        Visible
      </label>
      <button className="btn btn-primary" onClick={save} disabled={busy || !changed}>
        {busy ? "Guardando..." : "Guardar"}
      </button>
      {msg && <p className="w-full text-sm text-ink/70">{msg}</p>}
    </div>
  );
}

export default function AdminMenu({ items }: { items: FoodItem[] }) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [price, setPrice] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    setMsg(null);
    const p = Number(price.replace(",", "."));
    if (!name.trim()) return setMsg("Escribe un nombre.");
    if (!Number.isFinite(p) || p < 0 || p > 1000) return setMsg("Precio inválido.");
    setBusy(true);
    const sort = items.reduce((m, i) => Math.max(m, i.sort), 0) + 1;
    const { error } = await createClient().from("food_items").insert({ name: name.trim(), price: p, sort });
    setBusy(false);
    if (error) return setMsg(error.message);
    setName("");
    setPrice("");
    router.refresh();
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-white/60">
        Para marcar una pieza como agotada, quita la marca de &quot;Visible&quot; y guarda.
      </p>
      {items.map((i) => (
        <Row key={i.id} item={i} />
      ))}

      <form onSubmit={add} className="card flex flex-wrap items-end gap-3 p-4">
        <div className="min-w-[8rem] flex-1">
          <label className="mb-1 block text-xs font-medium">Nueva pieza</label>
          <input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} placeholder="Ej: Alita" />
        </div>
        <div className="w-28">
          <label className="mb-1 block text-xs font-medium">Precio (S/)</label>
          <input className="input" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} />
        </div>
        <button className="btn btn-gold" disabled={busy}>
          {busy ? "Agregando..." : "Agregar"}
        </button>
        {msg && <p className="w-full text-sm text-red-700">{msg}</p>}
      </form>
    </div>
  );
}
