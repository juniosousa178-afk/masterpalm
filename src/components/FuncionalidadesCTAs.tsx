"use client";

import Link from "next/link";
import { useSiteConfig } from "@/contexts/SiteConfigContext";

export function FuncionalidadesCTAs() {
  const config = useSiteConfig();

  return (
    <div className="mt-12 flex gap-4">
      <Link
        href="/download"
        className="inline-flex items-center gap-2 px-6 py-3 bg-accent-blue text-white rounded-xl font-medium hover:bg-accent-blue-light transition-colors"
      >
        Baixar APK
      </Link>
      <a
        href={config.APP_WEB_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-flex items-center gap-2 px-6 py-3 border border-silver-500/50 text-silver-400 rounded-xl font-medium hover:bg-graphite-800 hover:text-white transition-colors"
      >
        Acessar AppWeb
      </a>
    </div>
  );
}
