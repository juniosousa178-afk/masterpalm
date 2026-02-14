"use client";

import Link from "next/link";
import { siteConfig } from "@/config/site";

export function FloatingCTA() {
  return (
    <div
      className="fixed bottom-6 right-6 z-40 flex flex-col sm:flex-row gap-3"
      role="complementary"
      aria-label="Ações rápidas"
    >
      <a
        href={siteConfig.APP_WEB_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-flex items-center gap-2 px-5 py-3 bg-graphite-800 border border-silver-500/50 text-white rounded-full shadow-soft hover:bg-graphite-700 transition-all font-medium text-sm"
        aria-label="Acessar AppWeb em nova aba"
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
        </svg>
        AppWeb
      </a>
      <Link
        href="/download"
        className="inline-flex items-center gap-2 px-5 py-3 bg-accent-blue text-white rounded-full shadow-soft hover:bg-accent-blue-light transition-all font-medium text-sm shadow-glow"
        aria-label="Baixar APK do MasterPalm"
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
        </svg>
        Baixar APK
      </Link>
    </div>
  );
}
