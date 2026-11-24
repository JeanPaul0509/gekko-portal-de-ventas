import type { MetadataRoute } from "next";

const SITE_URL = "https://gekkofoodperu.vercel.app";

/** Páginas que Google puede mostrar (las demás piden iniciar sesión). */
export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return [
    { url: `${SITE_URL}/menu`, lastModified: now, changeFrequency: "daily", priority: 1 },
    { url: `${SITE_URL}/registro`, lastModified: now, changeFrequency: "monthly", priority: 0.5 },
    { url: `${SITE_URL}/terminos`, lastModified: now, changeFrequency: "monthly", priority: 0.3 },
  ];
}
