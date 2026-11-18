import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: profile } = await supabase.from("profiles").select("role").eq("id", user?.id ?? "").maybeSingle();
  if (profile?.role !== "admin") redirect("/menu");

  const tab = "rounded-xl bg-white/10 px-4 py-2 text-sm font-bold text-white hover:bg-white/15";
  return (
    <div className="space-y-5">
      <nav className="flex flex-wrap gap-2">
        <Link href="/admin/pedidos" className={tab}>
          Pedidos
        </Link>
        <Link href="/admin/menu" className={tab}>
          Menú
        </Link>
      </nav>
      {children}
    </div>
  );
}
