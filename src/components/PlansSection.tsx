import { siteConfig } from "@/config/site";

type Plan = (typeof siteConfig.plans)[number] & { badge?: string };

export function PlansSection() {
  const howItWorks = siteConfig.plansHowItWorks;

  return (
    <section
      id="planos"
      className="py-20 px-4 sm:px-6 lg:px-8"
      aria-labelledby="plans-title"
    >
      <div className="max-w-6xl mx-auto">
        <h2 id="plans-title" className="text-3xl sm:text-4xl font-bold text-white text-center mb-4">
          Planos
        </h2>
        <p className="text-gray-400 text-center mb-12 max-w-2xl mx-auto">
          Escolha como começar: teste grátis com experiência Pro no app, depois Free limitado se não assinar, ou vá direto ao Pro mensal/anual (valores finais no checkout conforme Remote Config).
        </p>

        {/* Como funcionam os planos */}
        <div className="mb-16 p-6 sm:p-8 rounded-2xl border border-graphite-700 bg-graphite-800/80">
          <h3 className="text-xl font-semibold text-white mb-6 flex items-center gap-2">
            <svg className="w-6 h-6 text-accent-blue" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            {howItWorks.title}
          </h3>
          <div className="space-y-6">
            {howItWorks.steps.map((step, i) => (
              <div key={i}>
                <h4 className="text-sm font-semibold text-accent-blue mb-1">{step.title}</h4>
                <p className="text-gray-400 text-sm leading-relaxed">{step.description}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="grid sm:grid-cols-3 gap-6">
          {siteConfig.plans.map((plan: Plan, index: number) => (
            <article
              key={index}
              className={`relative p-8 rounded-2xl border ${
                plan.badge === "Recomendado"
                  ? "bg-graphite-800 border-accent-blue shadow-glow"
                  : "bg-graphite-800/80 border-graphite-700"
              }`}
            >
              {plan.badge && (
                <span className="absolute top-4 right-4 px-3 py-1 rounded-full text-xs font-semibold bg-accent-blue/20 text-accent-blue border border-accent-blue/50">
                  {plan.badge}
                </span>
              )}
              <h3 className="text-xl font-semibold text-white mb-2 pr-24">{plan.name}</h3>
              <p className="text-2xl font-bold text-accent-blue mb-1">
                {plan.price}
                {"period" in plan && plan.period && (
                  <span className="text-base font-normal text-gray-400"> {plan.period}</span>
                )}
              </p>
              <ul className="space-y-3 mt-6">
                {plan.features.map((feature, i) => (
                  <li key={i} className="flex items-start gap-2 text-gray-400 text-sm">
                    <svg className="w-5 h-5 text-green-500 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                    {feature}
                  </li>
                ))}
              </ul>
            </article>
          ))}
        </div>

        <div className="mt-12 text-center">
          <a
            href={siteConfig.APP_WEB_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 px-8 py-4 rounded-xl font-semibold text-white bg-accent-blue hover:bg-accent-blue/90 transition-colors shadow-lg"
          >
            Começar agora
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
          </a>
          <p className="text-gray-500 text-sm mt-3">Abra o App Web para ativar seu plano ou fazer login.</p>
        </div>
      </div>
    </section>
  );
}
