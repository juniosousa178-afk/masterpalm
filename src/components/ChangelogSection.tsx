import { siteConfig } from "@/config/site";

export function ChangelogSection() {
  return (
    <section
      id="changelog"
      className="py-20 px-4 sm:px-6 lg:px-8"
      aria-labelledby="changelog-title"
    >
      <div className="max-w-4xl mx-auto">
        <h2 id="changelog-title" className="text-3xl sm:text-4xl font-bold text-white text-center mb-4">
          Changelog / Versões
        </h2>
        <p className="text-gray-400 text-center mb-12">
          Acompanhe as atualizações do MasterPalm
        </p>

        <div className="space-y-6">
          {siteConfig.changelog.map((release, index) => (
            <article
              key={index}
              className="p-6 rounded-2xl bg-graphite-800/80 border border-graphite-700"
            >
              <div className="flex flex-wrap items-center gap-2 mb-3">
                <span className="font-semibold text-white">v{release.version}</span>
                <span className="text-gray-500 text-sm">{release.date}</span>
              </div>
              <ul className="list-disc list-inside text-gray-400 text-sm space-y-1">
                {release.items.map((item, i) => (
                  <li key={i}>{item}</li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
