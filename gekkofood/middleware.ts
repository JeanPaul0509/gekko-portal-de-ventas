import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const AUTH_ROUTES = ["/login", "/registro"]; // solo sin sesión
// Se ven con o sin sesión (el menú es público para atraer clientes y para Google)
const OPEN_ROUTES = ["/terminos", "/menu", "/sitemap.xml", "/robots.txt"];

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Toda redirección debe llevar las cookies de sesión recién renovadas.
  // Si no, Supabase ya gastó el token viejo y la persona queda "botada" (sin sesión).
  const redirectTo = (url: URL) => {
    const r = NextResponse.redirect(url);
    response.cookies.getAll().forEach((c) => r.cookies.set(c));
    return r;
  };

  const path = request.nextUrl.pathname;
  const isAuthPage = AUTH_ROUTES.some((r) => path.startsWith(r));

  // La portada siempre lleva al menú
  if (path === "/") {
    const url = request.nextUrl.clone();
    url.pathname = "/menu";
    return redirectTo(url);
  }
  if (OPEN_ROUTES.some((r) => path.startsWith(r))) return response;

  // Sin sesión: al login, recordando a dónde quería ir (ej. el carrito)
  if (!user && !isAuthPage) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = `?next=${encodeURIComponent(path)}`;
    return redirectTo(url);
  }
  if (user && isAuthPage) {
    const next = request.nextUrl.searchParams.get("next");
    const url = request.nextUrl.clone();
    url.pathname = next && next.startsWith("/") && !next.startsWith("//") ? next : "/menu";
    url.search = "";
    return redirectTo(url);
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)"],
};
