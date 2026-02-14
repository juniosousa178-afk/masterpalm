import { siteConfig } from "@/config/site";

export function ScreenshotsMock() {
  return (
    <section
      className="py-20 px-4 sm:px-6 lg:px-8"
      aria-labelledby="screenshots-title"
    >
      <div className="max-w-6xl mx-auto">
        <h2 id="screenshots-title" className="text-3xl sm:text-4xl font-bold text-white text-center mb-4">
          APK e AppWeb
        </h2>
        <p className="text-gray-400 text-center mb-12 max-w-2xl mx-auto">
          Escolha a forma que melhor se adapta ao seu dia a dia
        </p>

        <div className="grid md:grid-cols-2 gap-12 items-center">
          <div className="space-y-4">
            <div className="p-6 rounded-2xl bg-graphite-800 border border-graphite-700">
              <h3 className="text-xl font-semibold text-white mb-2">📱 APK (Android)</h3>
              <p className="text-gray-400 text-sm leading-relaxed">
                Aplicativo nativo para Android. Instale no celular ou tablet e tenha acesso completo
                offline. Ideal para vendedores em campo ou lojas com conexão instável.
              </p>
            </div>
            <div className="p-6 rounded-2xl bg-graphite-800 border border-graphite-700">
              <h3 className="text-xl font-semibold text-white mb-2">🌐 AppWeb</h3>
              <p className="text-gray-400 text-sm leading-relaxed">
                Acesse pelo navegador em qualquer dispositivo. Sem instalação, sempre atualizado.
                Perfeito para administradores no computador ou uso em múltiplos dispositivos.
              </p>
            </div>
          </div>

          <div className="flex flex-col items-center justify-center">
            <div className="relative">
              <div className="w-48 h-96 rounded-3xl bg-graphite-800 border-4 border-graphite-600 shadow-2xl flex flex-col items-center justify-center p-6">
                <div className="w-16 h-6 rounded-full bg-graphite-700 mb-8" />
                <div className="space-y-4 w-full">
                  <div className="h-3 bg-graphite-700 rounded w-full" />
                  <div className="h-3 bg-graphite-700 rounded w-3/4" />
                  <div className="h-3 bg-graphite-700 rounded w-1/2" />
                  <div className="h-20 bg-graphite-700 rounded mt-8" />
                  <div className="h-20 bg-graphite-700 rounded" />
                </div>
                <p className="mt-6 text-xs text-gray-500">{siteConfig.name}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
