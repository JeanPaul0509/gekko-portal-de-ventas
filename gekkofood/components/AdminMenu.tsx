"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import SafeImg from "@/components/SafeImg";
import { createClient } from "@/lib/supabase/client";
import type { FoodItem } from "@/lib/food";
import { compressImage } from "@/lib/image";

const BUCKET = "raffle-images"; // el mismo de Gekko; las fotos del menú van en la carpeta comida/

/** "" = sin límite (null); número entero ≥ 0; undefined = inválido. */
function parseStock(v: string): number | null | undefined {
  const t = v.trim();
  if (t === "") return null;
  if (!/^\d+$/.test(t)) return undefined;
  const n = Number(t);
  return n <= 100000 ? n : undefined;
}

/** Sube una foto (ya comprimida) y devuelve su enlace público. */
async function uploadPhoto(file: File): Promise<string> {
  const supabase = createClient();
  const small = await compressImage(file);
  const ext = small.type === "image/jpeg" ? "jpg" : (small.name.split(".").pop() || "jpg").toLowerCase();
  const path = `comida/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, small, { cacheControl: "3600", upsert: false, contentType: small.type });
  if (error) throw new Error("No se pudo subir la foto: " + error.message);
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
}

/** Vista previa de la foto recién elegida. */
function usePreview(file: File | null) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (!file) {
      setUrl(null);
      return;
    }
    const u = URL.createObjectURL(file);
    setUrl(u);
    return () => URL.revokeObjectURL(u);
  }, [file]);
  return url;
}

function PhotoPicker({
  current,
  file,
  onFile,
  onRemove,
  removed,
}: {
  current: string | null;
  file: File | null;
  onFile: (f: File | null) => void;
  onRemove?: () => void;
  removed?: boolean;
}) {
  const preview = usePreview(file);
  const shown = preview ?? (removed ? null : current);
  return (
    <div className="flex items-center gap-3">
      <div className="h-16 w-16 shrink-0 overflow-hidden rounded-lg bg-gold-soft">
        <SafeImg src={shown} alt="Foto de la pieza" icon="🍗" iconClassName="text-2xl" className="h-full w-full object-cover" />
      </div>
      <div className="flex flex-col gap-1.5">
        <label className="btn btn-light cursor-pointer px-3! py-1.5! text-sm">
          {shown ? "Cambiar foto" : "Subir foto"}
          <input
            type="file"
            accept="image/*"
            className="sr-only"
            onChange={(e) => {
              onFile(e.target.files?.[0] ?? null);
              e.target.value = "";
            }}
          />
        </label>
        {shown && onRemove && (
          <button
            type="button"
            className="text-left text-xs font-semibold text-ruby underline underline-offset-4"
            onClick={() => {
              onFile(null);
              onRemove();
            }}
          >
            Quitar foto
          </button>
        )}
      </div>
    </div>
  );
}

function Row({ item }: { item: FoodItem }) {
  const router = useRouter();
  const [name, setName] = useState(item.name);
  const [price, setPrice] = useState(String(item.price));
  const [active, setActive] = useState(item.active);
  const [stock, setStock] = useState(item.stock === null ? "" : String(item.stock));
  const [file, setFile] = useState<File | null>(null);
  const [removed, setRemoved] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const p = Number(price.replace(",", "."));
  const st = parseStock(stock);
  const changed =
    name.trim() !== item.name ||
    p !== item.price ||
    active !== item.active ||
    file !== null ||
    removed ||
    st !== item.stock;

  async function save() {
    setMsg(null);
    if (!name.trim()) return setMsg("Escribe un nombre.");
    if (!Number.isFinite(p) || p < 0 || p > 1000) return setMsg("Precio inválido.");
    if (st === undefined) return setMsg("Unidades inválidas: escribe un número entero (o déjalo vacío para sin límite).");
    setBusy(true);
    try {
      let image_url: string | null = removed ? null : item.image_url;
      if (file) image_url = await uploadPhoto(file);
      const { error } = await createClient()
        .from("food_items")
        .update({ name: name.trim(), price: p, active, image_url, stock: st })
        .eq("id", item.id);
      if (error) throw new Error(error.message);
      setFile(null);
      setRemoved(false);
      setMsg("Guardado ✅");
      router.refresh();
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "No se pudo guardar.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card space-y-3 p-4">
      <div className="flex items-center justify-between gap-3">
        <PhotoPicker current={item.image_url} file={file} onFile={setFile} removed={removed} onRemove={() => setRemoved(true)} />
        <span className="rounded-full bg-paper px-3 py-1 text-xs font-bold">
          {item.kind === "bebida" ? "🥤 Bebida" : "🍗 Pieza"}
          {item.stock === 0 ? " · AGOTADO" : item.stock !== null ? ` · quedan ${item.stock}` : ""}
        </span>
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <div className="min-w-[8rem] flex-1">
          <label className="mb-1 block text-xs font-medium">Nombre</label>
          <input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} />
        </div>
        <div className="w-28">
          <label className="mb-1 block text-xs font-medium">Precio (S/)</label>
          <input className="input" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} />
        </div>
        <div className="w-32">
          <label className="mb-1 block text-xs font-medium">Unidades</label>
          <input
            className="input"
            inputMode="numeric"
            value={stock}
            onChange={(e) => setStock(e.target.value)}
            placeholder="Sin límite"
          />
        </div>
        <label className="flex items-center gap-2 pb-3 text-sm font-semibold">
          <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
          Visible
        </label>
        <button className="btn btn-primary" onClick={save} disabled={busy || !changed}>
          {busy ? "Guardando..." : "Guardar"}
        </button>
      </div>
      {msg && <p className="text-sm text-ink/70">{msg}</p>}
    </div>
  );
}

export default function AdminMenu({ items }: { items: FoodItem[] }) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [price, setPrice] = useState("");
  const [kind, setKind] = useState<"pieza" | "bebida">("pieza");
  const [newStock, setNewStock] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    setMsg(null);
    const p = Number(price.replace(",", "."));
    if (!name.trim()) return setMsg("Escribe un nombre.");
    if (!Number.isFinite(p) || p < 0 || p > 1000) return setMsg("Precio inválido.");
    const st = parseStock(newStock);
    if (st === undefined) return setMsg("Unidades inválidas: escribe un número entero (o déjalo vacío para sin límite).");
    setBusy(true);
    try {
      const image_url = file ? await uploadPhoto(file) : null;
      const sort = items.reduce((m, i) => Math.max(m, i.sort), 0) + 1;
      const { error } = await createClient().from("food_items").insert({ name: name.trim(), price: p, sort, image_url, kind, stock: st });
      if (error) throw new Error(error.message);
      setName("");
      setPrice("");
      setNewStock("");
      setFile(null);
      router.refresh();
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "No se pudo agregar.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-white/60">
        Pon en &quot;Unidades&quot; cuántas tienes de cada producto: cada pedido descuenta y, al llegar a 0, sale &quot;Agotado&quot;. Si lo dejas vacío, no tiene límite. Si cancelas un pedido, las unidades vuelven. Para ocultar un producto, quita &quot;Visible&quot;.
      </p>
      {items.map((i) => (
        <Row key={`${i.id}-${i.stock}`} item={i} />
      ))}

      <form onSubmit={add} className="card space-y-3 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-sm font-extrabold">Nuevo producto</p>
          <select className="input w-auto" value={kind} onChange={(e) => setKind(e.target.value as "pieza" | "bebida")}>
            <option value="pieza">🍗 Pieza de pollo (lleva papa/arroz y suma a la cartilla)</option>
            <option value="bebida">🥤 Bebida (sin acompañamiento, no suma)</option>
          </select>
        </div>
        <PhotoPicker current={null} file={file} onFile={setFile} />
        <div className="flex flex-wrap items-end gap-3">
          <div className="min-w-[8rem] flex-1">
            <label className="mb-1 block text-xs font-medium">Nombre</label>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} placeholder="Ej: Alita" />
          </div>
          <div className="w-28">
            <label className="mb-1 block text-xs font-medium">Precio (S/)</label>
            <input className="input" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} />
          </div>
          <div className="w-32">
            <label className="mb-1 block text-xs font-medium">Unidades</label>
            <input
              className="input"
              inputMode="numeric"
              value={newStock}
              onChange={(e) => setNewStock(e.target.value)}
              placeholder="Sin límite"
            />
          </div>
          <button className="btn btn-gold" disabled={busy}>
            {busy ? "Agregando..." : "Agregar"}
          </button>
        </div>
        {msg && <p className="text-sm text-red-700">{msg}</p>}
      </form>
    </div>
  );
}
