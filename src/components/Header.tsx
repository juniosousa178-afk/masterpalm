"use client";

import Link from "next/link";
import { useState } from "react";
import { siteConfig } from "@/config/site";

const navLinks = [
  { href: "/#funcionalidades", label: "Funcionalidades" },
  { href: "/#download", label: "Download" },
  { href: "/funcionalidades", label: "Recursos" },
  { href: "/#faq", label: "FAQ" },
  { href: "/#planos", label: "Planos" },
  { href: "/#changelog", label: "Changelog" },
  { href: "/#contato", label: "Contato" },
];

export function Header() {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <header
      className="fixed top-0 left-0 right-0 z-50 bg-graphite-950/95 backdrop-blur-md border-b border-graphite-800"
      role="banner"
    >
      <a
        href="#main-content"
        className="skip-link"
      >
        Pular para o conteúdo principal
      </a>
      <nav
        className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8"
        aria-label="Navegação principal"
      >
        <div className="flex items-center justify-between h-16">
          <Link
            href="/"
            className="text-xl font-bold text-silver-400 hover:text-white transition-colors"
            aria-label={`${siteConfig.name} - Página inicial`}
          >
            {siteConfig.name}
          </Link>

          {/* Desktop menu */}
          <ul className="hidden md:flex items-center gap-6">
            {navLinks.map((link) => (
              <li key={link.href}>
                <Link
                  href={link.href}
                  className="text-gray-300 hover:text-white transition-colors text-sm font-medium"
                >
                  {link.label}
                </Link>
              </li>
            ))}
            <li>
              <Link
                href="/download"
                className="inline-flex items-center px-4 py-2 bg-accent-blue text-white rounded-lg hover:bg-accent-blue-light transition-colors font-medium text-sm"
              >
                Baixar APK
              </Link>
            </li>
            <li>
              <a
                href={siteConfig.APP_WEB_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center px-4 py-2 border border-silver-500 text-silver-400 rounded-lg hover:bg-graphite-800 hover:text-white transition-colors font-medium text-sm"
              >
                AppWeb
              </a>
            </li>
          </ul>

          {/* Mobile menu button */}
          <button
            type="button"
            className="md:hidden p-2 text-gray-300 hover:text-white"
            onClick={() => setMobileOpen(!mobileOpen)}
            aria-expanded={mobileOpen}
            aria-controls="mobile-menu"
            aria-label={mobileOpen ? "Fechar menu" : "Abrir menu"}
          >
            <svg
              className="w-6 h-6"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              aria-hidden="true"
            >
              {mobileOpen ? (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              ) : (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              )}
            </svg>
          </button>
        </div>

        {/* Mobile menu */}
        <div
          id="mobile-menu"
          className={`md:hidden ${mobileOpen ? "block" : "hidden"} pb-4`}
          role="region"
          aria-label="Menu mobile"
        >
          <ul className="flex flex-col gap-2">
            {navLinks.map((link) => (
              <li key={link.href}>
                <Link
                  href={link.href}
                  className="block py-2 text-gray-300 hover:text-white"
                  onClick={() => setMobileOpen(false)}
                >
                  {link.label}
                </Link>
              </li>
            ))}
            <li className="pt-2 space-y-2">
              <Link
                href="/download"
                className="block w-full text-center py-3 bg-accent-blue text-white rounded-lg font-medium"
                onClick={() => setMobileOpen(false)}
              >
                Baixar APK
              </Link>
              <a
                href={siteConfig.APP_WEB_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="block w-full text-center py-3 border border-silver-500 text-silver-400 rounded-lg font-medium"
                onClick={() => setMobileOpen(false)}
              >
                Acessar AppWeb
              </a>
            </li>
          </ul>
        </div>
      </nav>
    </header>
  );
}
