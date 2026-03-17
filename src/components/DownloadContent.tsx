"use client";

import Link from "next/link";
import { useSiteConfig } from "@/contexts/SiteConfigContext";
import { siteConfig } from "@/config/site";

export function DownloadContent() {
  const config = useSiteConfig();

  return (
    <div className="pt-24 pb-20 px-4 sm:px-6 lg:px-8">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-3xl sm:text-4xl font-bold text-white mb-6">
          Download do MasterPalm
        </h1>

        <div className="space-y-8">
          <div className="flex flex-col sm:flex-row gap-4">
            <a
              href={config.PLAY_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 px-8 py-4 bg-accent-blue text-white rounded-xl font-semibold text-lg hover:bg-accent-blue-light transition-colors"
            >
              <svg className="w-6 h-6" viewBox="0 0 24 24" fill="currentColor">
                <path d="M3.609 1.814L13.792 12 3.61 22.186a.996.996 0 0 1-.61-.92V2.734a1 1 0 0 1 .609-.92zm10.89 10.893l2.302 2.302-10.937 6.333 8.635-8.635zm3.199-3.198l2.807 1.626a1 1 0 0 1 0 1.73l-2.808 1.626L15.206 12l2.492-2.491zM5.864 2.658L16.8 8.99l-2.302 2.302-8.634-8.634z"/>
              </svg>
              Baixar na Play Store
            </a>
            <a
              href={config.APK_DOWNLOAD_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 px-8 py-4 border-2 border-silver-500/50 text-silver-400 rounded-xl font-semibold text-lg hover:bg-graphite-800 hover:text-white transition-colors"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
              </svg>
              Baixar APK (alternativo)
            </a>
            <a
              href={config.APP_WEB_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 px-8 py-4 border-2 border-silver-500/50 text-silver-400 rounded-xl font-semibold text-lg hover:bg-graphite-800 hover:text-white transition-colors"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
              </svg>
              Acessar AppWeb
            </a>
          </div>

          <div className="p-6 rounded-2xl bg-graphite-800 border border-graphite-700">
            <h2 className="text-lg font-semibold text-white mb-4">Informações do app</h2>
            <ul className="space-y-2 text-gray-400 text-sm">
              <li><strong className="text-gray-300">Versão:</strong> {config.apkVersion}</li>
              <li><strong className="text-gray-300">Tamanho:</strong> {config.apkSize}</li>
              <li><strong className="text-gray-300">Data:</strong> {config.apkReleaseDate}</li>
            </ul>
          </div>

          <div className="p-6 rounded-2xl bg-graphite-800 border border-graphite-700">
            <h2 className="text-lg font-semibold text-white mb-4">Como instalar</h2>
            <ol className="space-y-4 text-gray-400 text-sm list-decimal list-inside">
              <li>
                <strong className="text-gray-300">Play Store (recomendado)</strong> — Clique em &quot;Baixar na Play Store&quot; e instale diretamente pelo Google Play. Mais seguro e atualização automática.
              </li>
              <li>
                <strong className="text-gray-300">APK (alternativo)</strong> — Se preferir instalar fora da Play Store, clique em &quot;Baixar APK&quot;. O arquivo será salvo no seu dispositivo.
              </li>
              <li>
                <strong className="text-gray-300">Ao usar APK: fontes desconhecidas</strong> — O Android bloqueia instalações fora da Play Store. Ative em <em>Configurações → Segurança</em> (ou <em>Apps</em>) — &quot;Instalar apps desconhecidos&quot; para o navegador.
              </li>
              <li>
                <strong className="text-gray-300">Instale e abra</strong> — Toque no arquivo APK baixado (ou conclua na Play Store) e abra o MasterPalm.
              </li>
            </ol>
          </div>

          <div className="p-6 rounded-2xl bg-amber-500/10 border border-amber-500/30">
            <h2 className="text-lg font-semibold text-amber-400 mb-2">Aviso de segurança</h2>
            <p className="text-gray-400 text-sm">
              Baixe o APK apenas pelo link oficial deste site. Não instale versões obtidas de terceiros, pois podem conter malware ou versões adulteradas. O link oficial está sempre disponível em {siteConfig.siteUrl}/download.
            </p>
          </div>
        </div>

        <div className="mt-10">
          <Link href="/" className="text-accent-blue hover:text-accent-blue-light font-medium">
            ← Voltar para a página inicial
          </Link>
        </div>
      </div>
    </div>
  );
}
