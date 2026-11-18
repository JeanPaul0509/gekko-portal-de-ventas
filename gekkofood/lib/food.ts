import { money, WHATSAPP_NUMBER } from "@/lib/utils";

export type Side = "papa" | "arroz";
export type FoodStatus = "pending" | "paid" | "delivered" | "cancelled";

export type FoodItem = { id: string; name: string; price: number; active: boolean; sort: number };
export type FoodCard = { points: number; goal: number; reward_ready: boolean };

export type FoodOrderItem = { id: number; name: string; side: Side | null; price: number; qty: number };
export type FoodOrder = {
  id: string;
  order_no: number;
  user_id: string | null;
  buyer_name: string;
  buyer_phone: string;
  address: string | null;
  note: string | null;
  total: number;
  is_reward: boolean;
  status: FoodStatus;
  created_at: string;
  food_order_items: FoodOrderItem[];
};

/** Pedidos que hay que completar para ganar el regalo (el valor real lo decide la base de datos). */
export const FOOD_GOAL = 7;
export const EMPTY_CARD: FoodCard = { points: 0, goal: FOOD_GOAL, reward_ready: false };

export const DELIVERY_NOTE =
  "Pide hasta las 10 a. m. y recibe de 1 a 2 p. m. en la Universidad ESAN. Atendemos lunes, martes, miércoles, viernes y sábado.";
export const DELIVERY_PLACE = "Universidad ESAN";
/** Hora límite (Lima) para que el pedido salga ese mismo día. */
export const CUTOFF_HOUR = 10;

const WEEK = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const NO_SERVICE = ["Thu", "Sun"]; // jueves y domingo no hay atención
const DAY_ES: Record<string, string> = {
  Sun: "domingo",
  Mon: "lunes",
  Tue: "martes",
  Wed: "miércoles",
  Thu: "jueves",
  Fri: "viernes",
  Sat: "sábado",
};

/** Próximo reparto para un pedido hecho ahora (solo para mostrar; hora de Lima). */
export function nextDelivery(now = new Date()) {
  const weekday = new Intl.DateTimeFormat("en-US", { timeZone: "America/Lima", weekday: "short" }).format(now);
  const hour = Number(
    new Intl.DateTimeFormat("en-US", { timeZone: "America/Lima", hour: "numeric", hourCycle: "h23" }).format(now)
  );
  const idx = WEEK.indexOf(weekday);
  const closedToday = NO_SERVICE.includes(weekday);
  let offset = !closedToday && hour < CUTOFF_HOUR ? 0 : 1;
  while (NO_SERVICE.includes(WEEK[(idx + offset) % 7]) && offset < 8) offset++;
  const day = WEEK[(idx + offset) % 7];
  const label = offset === 0 ? "hoy" : offset === 1 ? "mañana" : `el ${DAY_ES[day]}`;
  return { offset, label, closedToday, afterCutoff: hour >= CUTOFF_HOUR };
}

export function deliveryLine(now = new Date()) {
  const d = nextDelivery(now);
  const prefix = d.offset === 0 ? "" : d.closedToday ? "Hoy no hay atención. " : "Ya pasaron las 10 a. m.: ";
  const start = prefix ? "tu pedido de ahora" : "Tu pedido de ahora";
  return `${prefix}${start} se entrega ${d.label}, de 1 a 2 p. m., en la Universidad ESAN.`;
}

export const MAX_QTY = 20;

export const SIDES: { key: Side; label: string }[] = [
  { key: "papa", label: "Papa sola" },
  { key: "arroz", label: "Con arroz" },
];

export function sideLabel(side: Side | null | undefined) {
  if (side === "papa") return "papa sola";
  if (side === "arroz") return "con arroz";
  return "";
}

export const FOOD_STATUS: Record<FoodStatus, { label: string; cls: string }> = {
  pending: { label: "🟡 Esperando pago", cls: "bg-yellow-100 text-yellow-800" },
  paid: { label: "✅ Pagado", cls: "bg-green-100 text-green-700" },
  delivered: { label: "📦 Entregado", cls: "bg-gray-200 text-gray-700" },
  cancelled: { label: "Cancelado", cls: "bg-red-100 text-red-700" },
};

/** Los regalos no se pagan: se muestran con su propia etiqueta. */
export function statusChip(o: Pick<FoodOrder, "status" | "is_reward">) {
  if (o.is_reward && o.status === "paid") return { label: "🎁 Regalo confirmado", cls: "bg-green-100 text-green-700" };
  return FOOD_STATUS[o.status];
}

type Line = { name: string; side: Side | null; price: number; qty: number };

function itemLines(items: Line[]) {
  return items.map((i) => {
    const side = i.side ? ` (${sideLabel(i.side)})` : "";
    const sub = i.price > 0 ? ` — ${money(i.price * i.qty)}` : "";
    return `• ${i.qty} × ${i.name}${side}${sub}`;
  });
}

function toWa(phone: string) {
  const p = phone.replace(/\D/g, "");
  return p.length === 9 ? "51" + p : p;
}

/** Mensaje del cliente a Gekko Food con su pedido (luego adjunta la captura de Yape). */
export function buildFoodOrderWhatsAppUrl(opts: {
  orderNo: number;
  name: string;
  phone: string;
  address: string;
  note?: string | null;
  items: Line[];
  total: number;
}) {
  const text = [
    `¡Hola! 👋 Hice el pedido *N.º ${opts.orderNo}* en Gekko Food:`,
    "",
    ...itemLines(opts.items),
    "",
    `💰 Total a pagar: *${money(opts.total)}*`,
    `👤 Nombre: ${opts.name}`,
    `📱 Celular: ${opts.phone}`,
    `📍 Entrega en ESAN (1 a 2 p. m.): ${opts.address}`,
    ...(opts.note ? [`📝 Nota: ${opts.note}`] : []),
    "",
    "📎 *Adjunto captura de Yape* 👇",
  ].join("\n");
  // api.whatsapp.com conserva los emojis; wa.me a veces los rompe al redirigir
  return `https://api.whatsapp.com/send?phone=${WHATSAPP_NUMBER}&text=${encodeURIComponent(text)}`;
}

/** Mensaje del cliente para confirmar el regalo de su cartilla. */
export function buildRewardWhatsAppUrl(opts: {
  orderNo: number;
  name: string;
  phone: string;
  address: string;
  note?: string | null;
  label: string;
}) {
  const text = [
    `¡Hola! 🎁 Completé mi cartilla de Gekko Food y quiero canjear mi regalo (pedido *N.º ${opts.orderNo}*):`,
    "",
    `• ${opts.label}`,
    "",
    `👤 Nombre: ${opts.name}`,
    `📱 Celular: ${opts.phone}`,
    `📍 Entrega en ESAN (1 a 2 p. m.): ${opts.address}`,
    ...(opts.note ? [`📝 Nota: ${opts.note}`] : []),
  ].join("\n");
  return `https://api.whatsapp.com/send?phone=${WHATSAPP_NUMBER}&text=${encodeURIComponent(text)}`;
}

/** Mensaje de Gekko Food al cliente cuando cambia el estado de su pedido. */
export function foodStatusWhatsAppUrl(opts: {
  phone: string;
  name: string;
  orderNo: number;
  status: FoodStatus;
  isReward: boolean;
  items: Line[];
  total: number;
}) {
  const first = opts.name.trim().split(/\s+/)[0] || "";
  const hi = `¡Hola${first ? " " + first : ""}!`;
  const head =
    opts.status === "paid"
      ? opts.isReward
        ? `${hi} 🎁 Confirmamos tu regalo del pedido *N.º ${opts.orderNo}*.`
        : `${hi} ✅ Confirmamos tu pago del pedido *N.º ${opts.orderNo}*.`
      : opts.status === "delivered"
        ? `${hi} 📦 Tu pedido *N.º ${opts.orderNo}* ya fue entregado. ¡Gracias por tu compra!`
        : opts.status === "cancelled"
          ? `${hi} Tu pedido *N.º ${opts.orderNo}* fue cancelado.`
          : `${hi} Sobre tu pedido *N.º ${opts.orderNo}*:`;
  const text = [head, "", ...itemLines(opts.items), ...(opts.total > 0 ? [`💰 Total: ${money(opts.total)}`] : [])].join(
    "\n"
  );
  return `https://api.whatsapp.com/send?phone=${toWa(opts.phone)}&text=${encodeURIComponent(text)}`;
}
