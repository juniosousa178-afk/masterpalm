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
              href={config.APK_DOWNLOAD_URL}
              className="inline-flex items-center justify-center gap-2 px-8 py-4 bg-accent-blue text-white rounded-xl font-semibold text-lg hover:bg-accent-blue-light transition-colors"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
              </svg>
              Baixar APK
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
            <h2 className="text-lg font-semibold text-white mb-4">Informações do APK</h2>
            <ul className="space-y-2 text-gray-400 text-sm">
              <li><strong className="text-gray-300">Versão:</strong> {config.apkVersion}</li>
              <li><strong className="text-gray-300">Tamanho:</strong> {config.apkSize}</li>
              <li><strong className="text-gray-300">Data:</strong> {config.apkReleaseDate}</li>
            </ul>
          </div>

          <div className="p-6 rounded-2xl bg-graphite-800 border border-graphite-700">
            <h2 className="text-lg font-semibold text-white mb-4">Como instalar o APK no Android</h2>
            <ol className="space-y-4 text-gray-400 text-sm list-decimal list-inside">
              <li>
                <strong className="text-gray-300">Baixe o arquivo</strong> — Clique no botão &quot;Baixar APK&quot; acima. O arquivo será salvo no seu dispositivo.
              </li>
              <li>
                <strong className="text-gray-300">Permita instalação de fontes desconhecidas</strong> — O Android, por segurança, bloqueia instalações de apps fora da Play Store. Você precisará permitir nas configurações do dispositivo. Vá em <em>Configurações → Segurança</em> (ou <em>Apps</em>) e ative &quot;Fontes desconhecidas&quot; ou &quot;Instalar apps desconhecidos&quot; para o navegador ou gerenciador de arquivos que você usa. Isso é seguro quando o arquivo vem do link oficial.
              </li>
              <li>
                <strong className="text-gray-300">Instale e abra</strong> — Toque no arquivo baixado e siga as instruções na tela. Depois da instalação, abra o MasterPalm normalmente.
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
