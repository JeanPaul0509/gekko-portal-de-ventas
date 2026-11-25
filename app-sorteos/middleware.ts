import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const AUTH_ROUTES = ["/login", "/registro"]; // solo sin sesión
const OPEN_ROUTES = ["/terminos", "/privacidad", "/api/whatsapp"]; // con o sin sesión (el aviso de Meta no trae sesión)

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
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
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
  const isOpen = OPEN_ROUTES.some((r) => path.startsWith(r));

  if (!user && !isAuthPage && !isOpen) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return redirectTo(url);
  }
  if (user && (isAuthPage || path === "/")) {
    const url = request.nextUrl.clone();
    url.pathname = "/tienda";
    return redirectTo(url);
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)"],
};
