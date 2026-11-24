import type { Metadata, Viewport } from "next";
import "./globals.css";

const SITE_URL = "https://gekkofoodperu.vercel.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Gekko Food | Pollo broaster en la Universidad ESAN",
    template: "%s | Gekko Food",
  },
  description:
    "Pollo broaster: pecho, pierna, entrepierna y ala con papa y arroz. Pide en la web, paga con Yape y recíbelo en la Universidad ESAN. Junta piezas en tu cartilla y gana tu regalo.",
  keywords: ["pollo broaster", "broaster ESAN", "Universidad ESAN", "almuerzo ESAN", "Gekko Food", "pollo Surco", "delivery ESAN"],
  applicationName: "Gekko Food",
  openGraph: {
    type: "website",
    locale: "es_PE",
    url: SITE_URL,
    siteName: "Gekko Food",
    title: "Gekko Food | Pollo broaster en la Universidad ESAN",
    description: "Pide tu pollo broaster hasta las 10 a. m. y recíbelo de 12:30 a 2:00 p. m. en la Universidad ESAN.",
  },
  robots: { index: true, follow: true },
  // Código de Google Search Console: se pone en Vercel como GOOGLE_SITE_VERIFICATION
  verification: process.env.GOOGLE_SITE_VERIFICATION ? { google: process.env.GOOGLE_SITE_VERIFICATION } : undefined,
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#1d1814",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@100..125,400..800&family=Cormorant+Garamond:wght@500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="min-h-screen font-sans antialiased">{children}</body>
    </html>
  );
}
