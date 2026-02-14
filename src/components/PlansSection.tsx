import { siteConfig } from "@/config/site";

export function PlansSection() {
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
          Em breve teremos planos para atender diferentes necessidades
        </p>

        <div className="grid sm:grid-cols-3 gap-6">
          {siteConfig.plans.map((plan, index) => (
            <article
              key={index}
              className={`p-8 rounded-2xl border ${
                index === 1
                  ? "bg-graphite-800 border-accent-blue shadow-glow"
                  : "bg-graphite-800/80 border-graphite-700"
              }`}
            >
              <h3 className="text-xl font-semibold text-white mb-2">{plan.name}</h3>
              <p className="text-2xl font-bold text-accent-blue mb-6">{plan.price}</p>
              <ul className="space-y-3">
                {plan.features.map((feature, i) => (
                  <li key={i} className="flex items-center gap-2 text-gray-400 text-sm">
                    <svg className="w-5 h-5 text-green-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                    {feature}
                  </li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
