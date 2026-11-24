import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: ["/", "/menu", "/terminos", "/registro", "/login"],
      disallow: ["/admin", "/carrito", "/cartilla", "/mis-pedidos"],
    },
    sitemap: "https://gekkofoodperu.vercel.app/sitemap.xml",
  };
}
