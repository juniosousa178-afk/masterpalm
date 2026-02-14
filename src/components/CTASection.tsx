import Link from "next/link";
import { siteConfig } from "@/config/site";

export function CTASection() {
  return (
    <section
      id="download"
      className="py-20 px-4 sm:px-6 lg:px-8 bg-gradient-to-b from-graphite-900 to-graphite-950"
      aria-labelledby="cta-title"
    >
      <div className="max-w-4xl mx-auto text-center">
        <h2 id="cta-title" className="text-3xl sm:text-4xl font-bold text-white mb-4">
          Comece agora
        </h2>
        <p className="text-gray-400 mb-10 max-w-xl mx-auto">
          Baixe o APK para Android ou acesse o AppWeb diretamente no navegador
        </p>
        <div className="flex flex-col sm:flex-row gap-4 justify-center">
          <Link
            href="/download"
            className="inline-flex items-center justify-center gap-2 px-8 py-4 bg-accent-blue text-white rounded-xl font-semibold text-lg hover:bg-accent-blue-light transition-colors"
          >
            Baixar APK
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
            </svg>
          </Link>
          <a
            href={siteConfig.APP_WEB_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center justify-center gap-2 px-8 py-4 border-2 border-silver-500/50 text-silver-400 rounded-xl font-semibold text-lg hover:bg-graphite-800 hover:text-white transition-colors"
          >
            Acessar AppWeb
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
          </a>
        </div>
      </div>
    </section>
  );
}
