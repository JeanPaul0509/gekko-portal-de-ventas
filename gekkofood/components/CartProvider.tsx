"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { MAX_QTY, type CartSide } from "@/lib/food";

export type CartLine = { itemId: string; side: CartSide; qty: number };

type Ctx = {
  lines: CartLine[];
  count: number;
  ready: boolean;
  add: (itemId: string, side: CartSide) => void;
  setQty: (itemId: string, side: CartSide, qty: number) => void;
  remove: (itemId: string, side: CartSide) => void;
  clear: () => void;
};

const CartCtx = createContext<Ctx | null>(null);
const KEY = "gekkofood-cart-v1";

function isLine(x: unknown): x is CartLine {
  if (!x || typeof x !== "object") return false;
  const l = x as Record<string, unknown>;
  return (
    typeof l.itemId === "string" &&
    (l.side === "papa_arroz" || l.side === "arroz") &&
    typeof l.qty === "number" &&
    l.qty >= 1
  );
}

export function CartProvider({ children }: { children: React.ReactNode }) {
  const [lines, setLines] = useState<CartLine[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(KEY);
      const parsed = raw ? JSON.parse(raw) : [];
      if (Array.isArray(parsed)) setLines(parsed.filter(isLine).map((l) => ({ ...l, qty: Math.min(l.qty, MAX_QTY) })));
    } catch {
      // carrito dañado: se empieza vacío
    }
    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    try {
      localStorage.setItem(KEY, JSON.stringify(lines));
    } catch {
      // sin almacenamiento: el carrito vive solo en esta visita
    }
  }, [lines, ready]);

  const add = useCallback((itemId: string, side: CartSide) => {
    setLines((prev) => {
      const i = prev.findIndex((l) => l.itemId === itemId && l.side === side);
      if (i === -1) return [...prev, { itemId, side, qty: 1 }];
      return prev.map((l, k) => (k === i ? { ...l, qty: Math.min(MAX_QTY, l.qty + 1) } : l));
    });
  }, []);

  const setQty = useCallback((itemId: string, side: CartSide, qty: number) => {
    setLines((prev) =>
      qty < 1
        ? prev.filter((l) => !(l.itemId === itemId && l.side === side))
        : prev.map((l) => (l.itemId === itemId && l.side === side ? { ...l, qty: Math.min(MAX_QTY, qty) } : l))
    );
  }, []);

  const remove = useCallback((itemId: string, side: CartSide) => {
    setLines((prev) => prev.filter((l) => !(l.itemId === itemId && l.side === side)));
  }, []);

  const clear = useCallback(() => setLines([]), []);

  const value = useMemo<Ctx>(
    () => ({ lines, count: lines.reduce((a, l) => a + l.qty, 0), ready, add, setQty, remove, clear }),
    [lines, ready, add, setQty, remove, clear]
  );

  return <CartCtx.Provider value={value}>{children}</CartCtx.Provider>;
}

export function useCart() {
  const ctx = useContext(CartCtx);
  if (!ctx) throw new Error("useCart debe usarse dentro de CartProvider");
  return ctx;
}
