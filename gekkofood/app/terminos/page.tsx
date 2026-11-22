import Link from "next/link";
import Brand from "@/components/Brand";
import TermsText from "@/components/TermsText";
import { FOOD_TERMS } from "@/lib/terms";

export const metadata = { title: "Términos y condiciones | Gekko Food" };

export default function TerminosPage() {
  return (
    <div className="min-h-screen">
      <header className="border-b border-gold/25 bg-brand/90">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-4 py-3">
          <Brand />
          <Link href="/menu" className="text-sm font-semibold text-white/80 hover:text-white">
            Volver
          </Link>
        </div>
      </header>
      <main className="mx-auto max-w-3xl px-4 py-8">
        <h1 className="font-display text-4xl font-semibold text-white">Términos y condiciones</h1>
        <p className="mt-1 text-sm text-white/60">Gekko Food · pollo broaster</p>
        <article className="card mt-6 p-6 sm:p-8">
          <TermsText text={FOOD_TERMS} />
        </article>
      </main>
    </div>
  );
}
