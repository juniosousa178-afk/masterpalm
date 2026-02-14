import type { Metadata } from "next";
import { Plus_Jakarta_Sans } from "next/font/google";
import "./globals.css";
import { siteConfig } from "@/config/site";
import { SiteConfigProvider } from "@/contexts/SiteConfigContext";

const plusJakarta = Plus_Jakarta_Sans({
  subsets: ["latin"],
  variable: "--font-plus-jakarta",
});
import { Header } from "@/components/Header";
import { FloatingCTA } from "@/components/FloatingCTA";
import { Footer } from "@/components/Footer";

export const metadata: Metadata = {
  title: {
    default: `${siteConfig.name} | Sistema de Gestão para Lojas`,
    template: `%s | ${siteConfig.name}`,
  },
  description: siteConfig.description,
  keywords: ["gestão de loja", "controle de estoque", "vendas", "relatórios", "Android", "app web"],
  authors: [{ name: siteConfig.name }],
  creator: siteConfig.name,
  openGraph: {
    type: "website",
    locale: "pt_BR",
    url: siteConfig.siteUrl,
    siteName: siteConfig.name,
    title: siteConfig.name,
    description: siteConfig.description,
  },
  twitter: {
    card: "summary_large_image",
    title: siteConfig.name,
    description: siteConfig.description,
  },
  robots: {
    index: true,
    follow: true,
  },
  metadataBase: new URL(siteConfig.siteUrl),
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR" className="scroll-smooth">
      <head>
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
      </head>
      <body className={`${plusJakarta.variable} font-sans antialiased bg-graphite-950 text-gray-100 min-h-screen`}>
        <SiteConfigProvider>
          <Header />
          <main id="main-content" role="main">
            {children}
          </main>
          <Footer />
          <FloatingCTA />
        </SiteConfigProvider>
      </body>
    </html>
  );
}
