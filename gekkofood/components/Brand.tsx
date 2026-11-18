import Link from "next/link";

/** Mismo monograma G de Gekko, para que se vea que es de la misma marca. */
function Monogram({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={className} aria-hidden>
      <rect width="64" height="64" rx="15" fill="#1d1814" />
      <rect x="1" y="1" width="62" height="62" rx="14" fill="none" stroke="#d6ad5a" strokeOpacity="0.45" strokeWidth="2" />
      <path
        d="M41.7 22.3 A13.75 13.75 0 1 0 45.75 32 H34"
        fill="none"
        stroke="#d6ad5a"
        strokeWidth="5.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export default function Brand({ size = "md" }: { size?: "md" | "lg" }) {
  return (
    <Link href="/menu" aria-label="Gekko Food, ir al menú" className="flex items-center gap-2.5 rounded-lg">
      <Monogram className={size === "lg" ? "h-12 w-12" : "h-8 w-8"} />
      <span className="flex flex-col leading-none">
        <span
          className={`font-display font-bold uppercase tracking-[0.22em] text-white ${
            size === "lg" ? "text-4xl" : "text-[1.35rem]"
          }`}
        >
          Gekko
        </span>
        <span
          className={`mt-1 font-semibold uppercase tracking-[0.5em] text-gold ${
            size === "lg" ? "text-[0.8rem]" : "text-[0.58rem]"
          }`}
        >
          Food
        </span>
      </span>
    </Link>
  );
}
