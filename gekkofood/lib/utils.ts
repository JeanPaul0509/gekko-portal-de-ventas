// Los celulares se guardan como "correo" interno (igual que en Gekko) para que
// la MISMA cuenta funcione en las dos páginas.
export const PHONE_DOMAIN = "celular.sorteos.app";

export function cleanPhone(raw: string) {
  return raw.replace(/\D/g, "").replace(/^51(?=9\d{8}$)/, "");
}

export function isValidPhone(phone: string) {
  return /^9\d{8}$/.test(phone);
}

export function phoneToEmail(phone: string) {
  return `${phone}@${PHONE_DOMAIN}`;
}

const MONEY = new Intl.NumberFormat("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const INT = new Intl.NumberFormat("es-PE");

/** S/ 1,234.50 */
export function money(v: number | string) {
  const n = Number(v);
  return `S/ ${MONEY.format(Number.isFinite(n) ? n : 0)}`;
}

/** 1,284 */
export function num(v: number | string | null | undefined) {
  const n = Number(v ?? 0);
  return INT.format(Number.isFinite(n) ? n : 0);
}

/** "1 pedido" / "3 pedidos" */
export function plural(n: number, one: string, many: string) {
  return `${num(n)} ${n === 1 ? one : many}`;
}

/** WhatsApp que recibe TODOS los pedidos y capturas de pago (el mismo de Gekko). */
export const WHATSAPP_NUMBER = "51912389459";

export const YAPE_NUMBER = process.env.NEXT_PUBLIC_YAPE_NUMBER ?? "";
export const YAPE_NAME = process.env.NEXT_PUBLIC_YAPE_NAME ?? "";

export function formatDate(iso: string | null) {
  if (!iso) return "";
  return new Date(iso).toLocaleString("es-PE", { dateStyle: "short", timeStyle: "short" });
}
