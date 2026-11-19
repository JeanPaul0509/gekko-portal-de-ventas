import Brand from "@/components/Brand";

export default function AuthShell({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen flex-col">
      <div className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center px-4 py-10">
        <div className="anim-rise mb-8 flex justify-center">
          <Brand size="lg" />
        </div>
        <div className="ticket auth-ticket p-7" style={{ ["--cut" as string]: "calc(100% - 3.75rem)" }}>
          <h1 className="text-2xl font-extrabold">{title}</h1>
          <p className="mb-6 mt-1 text-sm text-gray-500">{subtitle}</p>
          {children}
          <div className="ticket-perf" style={{ margin: "1.75rem -0.9rem 0" }} />
          <p className="pt-4 text-center text-xs text-gray-500">
            Si ya tienes cuenta en Gekko, entra con el mismo celular y la misma contraseña.
          </p>
        </div>
        <ul className="anim-rise mt-8 space-y-2 text-sm text-white/70" style={{ ["--delay" as string]: "450ms" }}>
          <li className="flex gap-2"><span className="text-gold">✓</span>Pollo broaster con papa y arroz, o solo arroz.</li>
          <li className="flex gap-2"><span className="text-gold">✓</span>Pides en la app y pagas con Yape.</li>
          <li className="flex gap-2"><span className="text-gold">✓</span>Cada pedido llena una bolita: tu 8.º pedido es de regalo.</li>
        </ul>
        <p className="mt-8 text-center text-xs text-white/50">
          <a href="https://gekkoperu.vercel.app/terminos" className="underline underline-offset-4 hover:text-white">
            Términos y condiciones
          </a>
        </p>
      </div>
    </div>
  );
}
