"use client";

import Link from "next/link";
import { siteConfig } from "@/config/site";
import { useSiteConfig } from "@/contexts/SiteConfigContext";
import { getMailtoHref } from "@/lib/urlUtils";

export function Footer() {
  const config = useSiteConfig();
  const currentYear = new Date().getFullYear();

  return (
    <footer
      className="bg-graphite-950 border-t border-graphite-800 py-12 px-4 sm:px-6 lg:px-8"
      role="contentinfo"
    >
      <div className="max-w-6xl mx-auto">
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-8 mb-8">
          <div>
            <h3 className="font-bold text-white text-lg mb-4">{siteConfig.name}</h3>
            <p className="text-gray-400 text-sm">{siteConfig.slogan}</p>
          </div>
          <div>
            <h4 className="font-semibold text-white mb-4">Links</h4>
            <ul className="space-y-2">
              <li>
                <Link href="/funcionalidades" className="text-gray-400 hover:text-white text-sm">
                  Funcionalidades
                </Link>
              </li>
              <li>
                <Link href="/download" className="text-gray-400 hover:text-white text-sm">
                  Download
                </Link>
              </li>
              <li>
                <a href={config.APP_WEB_URL} target="_blank" rel="noopener noreferrer" className="text-gray-400 hover:text-white text-sm">
                  AppWeb
                </a>
              </li>
              <li>
                <Link href="/politica-de-privacidade" className="text-gray-400 hover:text-white text-sm">
                  Política de Privacidade
                </Link>
              </li>
              <li>
                <Link href="/termos" className="text-gray-400 hover:text-white text-sm">
                  Termos de Uso
                </Link>
              </li>
            </ul>
          </div>
          <div>
            <h4 className="font-semibold text-white mb-4">Contato</h4>
            <ul className="space-y-2">
              <li>
                <a href={getMailtoHref(config.SUPPORT_EMAIL)} className="text-gray-400 hover:text-white text-sm">
                  {config.SUPPORT_EMAIL}
                </a>
              </li>
              <li>
                <a href={config.SUPPORT_WHATSAPP_URL} target="_blank" rel="noopener noreferrer" className="text-gray-400 hover:text-white text-sm">
                  WhatsApp
                </a>
              </li>
              <li>
                <a href={config.INSTAGRAM_URL.startsWith("http") ? config.INSTAGRAM_URL : `https://instagram.com/${config.INSTAGRAM_URL.replace(/^@/, "")}`} target="_blank" rel="noopener noreferrer" className="text-gray-400 hover:text-white text-sm">
                  Instagram
                </a>
              </li>
            </ul>
          </div>
          <div>
            <h4 className="font-semibold text-white mb-4">Legal</h4>
            <ul className="space-y-2">
              <li>
                <Link href="/politica-de-privacidade" className="text-gray-400 hover:text-white text-sm">
                  Política de Privacidade
                </Link>
              </li>
              <li>
                <Link href="/termos" className="text-gray-400 hover:text-white text-sm">
                  Termos de Uso
                </Link>
              </li>
            </ul>
          </div>
        </div>
        <div className="pt-8 border-t border-graphite-800 text-center text-gray-500 text-sm">
          <p>© {currentYear} {siteConfig.name}. Todos os direitos reservados.</p>
        </div>
      </div>
    </footer>
  );
}
