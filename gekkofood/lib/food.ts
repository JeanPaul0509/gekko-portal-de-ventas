import { money, WHATSAPP_NUMBER } from "@/lib/utils";

/** papa_arroz = papa y arroz · arroz = solo arroz · papa_chaufa / chaufa = lo mismo con chaufa (promo de cartilla llena) · papa = papa sola (pedidos antiguos) */
export type Side = "papa" | "papa_arroz" | "arroz" | "papa_chaufa" | "chaufa";
export type Reward = "chaufa" | "hamburguesa";
/** Lo que se puede elegir hoy en el carrito. */
export type CartSide = "papa_arroz" | "arroz" | "sin"; // "sin" = bebidas (no llevan acompañamiento)
export type FoodKind = "pieza" | "bebida";
export type FoodStatus = "pending" | "paid" | "delivered" | "cancelled";

export type FoodItem = { id: string; name: string; price: number; active: boolean; sort: number; image_url: string | null; kind: FoodKind };
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
  reward_choice: Reward | null;
  status: FoodStatus;
  created_at: string;
  food_order_items: FoodOrderItem[];
};

/** Pedidos que hay que completar para ganar el regalo (el valor real lo decide la base de datos). */
export const FOOD_GOAL = 7;
export const EMPTY_CARD: FoodCard = { points: 0, goal: FOOD_GOAL, reward_ready: false };

export const DELIVERY_NOTE =
  "Reserva tu pedido hasta las 10 a. m. y recíbelo de 12:30 a 2:00 p. m. en la Universidad ESAN. Atendemos lunes, martes, miércoles, viernes y sábado.";
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
  // Fecha del día de entrega (Perú no cambia de hora, así que sumar días exactos funciona)
  const dayNum = new Intl.DateTimeFormat("en-US", { timeZone: "America/Lima", day: "numeric" }).format(
    new Date(now.getTime() + offset * 86_400_000)
  );
  const dayName = `${DAY_ES[day]} ${dayNum}`; // "viernes 20"
  const label = offset === 0 ? `hoy ${dayName}` : offset === 1 ? `mañana ${dayName}` : `el ${dayName}`;
  return { offset, label, dayName, closedToday, afterCutoff: hour >= CUTOFF_HOUR };
}

export const DELIVERY_HOURS = "de 12:30 a 2:00 p. m.";

/** Recuadro dorado del menú y del carrito. */
export function deliveryLine(now = new Date()) {
  const d = nextDelivery(now);
  if (d.offset === 0) return `Para hoy ${d.dayName} · entrega ${DELIVERY_HOURS} en la Universidad ESAN`;
  return `Reserva para ${d.label} · entrega ${DELIVERY_HOURS} en la Universidad ESAN`;
}

/** Aviso que hay que aceptar antes de pedir cuando el pedido ya no sale hoy. null = sale hoy. */
export function lateNotice(now = new Date()): { title: string; body: string } | null {
  const d = nextDelivery(now);
  if (d.offset === 0) return null;
  if (d.closedToday) {
    return {
      title: `Tu pedido será para ${d.label}`,
      body: `Los jueves y domingos no repartimos. Reserva ahora y te lo entregamos ${d.label}, ${DELIVERY_HOURS}, en la Universidad ESAN.`,
    };
  }
  return {
    title: "Hoy ya se repartieron los pedidos",
    body: `Ya pasaron las 10 a. m. Reserva ahora y te lo entregamos ${d.label}, ${DELIVERY_HOURS}, en la Universidad ESAN.`,
  };
}

export const MAX_QTY = 20;

export const SIDES: { key: CartSide; label: string }[] = [
  { key: "papa_arroz", label: "Papa y arroz" },
  { key: "arroz", label: "Solo arroz" },
];

export function sideLabel(side: Side | CartSide | null | undefined) {
  if (side === "papa_arroz") return "papa y arroz";
  if (side === "arroz") return "solo arroz";
  if (side === "papa_chaufa") return "papa y chaufa";
  if (side === "chaufa") return "solo chaufa";
  if (side === "papa") return "papa sola";
  return "";
}

export const FOOD_STATUS: Record<FoodStatus, { label: string; cls: string }> = {
  pending: { label: "🟡 Esperando pago", cls: "bg-yellow-100 text-yellow-800" },
  paid: { label: "✅ Pagado", cls: "bg-green-100 text-green-700" },
  delivered: { label: "📦 Entregado", cls: "bg-gray-200 text-gray-700" },
  cancelled: { label: "Cancelado", cls: "bg-red-100 text-red-700" },
};

export function statusChip(o: Pick<FoodOrder, "status">) {
  return FOOD_STATUS[o.status];
}

/** ¿Esta línea es el regalo de la promo? (la pieza con chaufa o la hamburguesa) */
export function isPromoLine(i: { side: Side | null; price: number }) {
  return i.side === "papa_chaufa" || i.side === "chaufa" || (i.price === 0 && i.side === null);
}

/** Texto corto de la promo de cartilla llena (para tarjetas y mensajes). */
export const REWARD_TEXT: Record<Reward, string> = {
  chaufa: "1 pieza con chaufa en vez de arroz blanco",
  hamburguesa: "Hamburguesa de regalo",
};

type Line = { name: string; side: Side | null; price: number; qty: number };

function itemLines(items: Line[]) {
  return items.map((i) => {
    const side = i.side ? ` (${sideLabel(i.side)})` : "";
    const sub = i.price > 0 ? ` — ${money(i.price * i.qty)}` : "";
    return `${isPromoLine(i) ? "🎁" : "•"} ${i.qty} × ${i.name}${side}${sub}${isPromoLine(i) ? " (promo)" : ""}`;
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
  /** "hoy", "mañana", "el viernes"... según la hora en que se pidió */
  forDay?: string;
  /** regalo de la cartilla llena */
  reward?: Reward | null;
}) {
  const text = [
    `¡Hola! 👋 Hice el pedido *N.º ${opts.orderNo}* en Gekko Food:`,
    "",
    ...itemLines(opts.items),
    "",
    `💰 Total a pagar: *${money(opts.total)}*`,
    `👤 Nombre: ${opts.name}`,
    `📱 Celular: ${opts.phone}`,
    `📍 Entrega en ESAN (12:30 a 2:00 p. m.): ${opts.address}`,
    ...(opts.forDay ? [`🕐 Para: ${opts.forDay}`] : []),
    ...(opts.reward ? [`🎁 Promo cartilla llena: ${REWARD_TEXT[opts.reward]}`] : []),
    ...(opts.note ? [`📝 Nota: ${opts.note}`] : []),
    "",
    "📎 *Adjunto captura de Yape* 👇",
  ].join("\n");
  // api.whatsapp.com conserva los emojis; wa.me a veces los rompe al redirigir
  return `https://api.whatsapp.com/send?phone=${WHATSAPP_NUMBER}&text=${encodeURIComponent(text)}`;
}

/** Mensaje de Gekko Food al cliente cuando cambia el estado de su pedido. */
export function foodStatusWhatsAppUrl(opts: {
  phone: string;
  name: string;
  orderNo: number;
  status: FoodStatus;
  items: Line[];
  total: number;
}) {
  const first = opts.name.trim().split(/\s+/)[0] || "";
  const hi = `¡Hola${first ? " " + first : ""}!`;
  const head =
    opts.status === "paid"
      ? `${hi} ✅ Confirmamos tu pago del pedido *N.º ${opts.orderNo}*.`
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
