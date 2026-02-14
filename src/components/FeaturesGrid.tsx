import { siteConfig } from "@/config/site";

const features = [
  {
    title: "Controle de estoque",
    description: "Baixa automática em vendas, alertas de estoque baixo e gestão completa do inventário.",
    icon: "📦",
  },
  {
    title: "Produtos com variações",
    description: "Cadastro com tamanho, cor e outras variações para flexibilidade total.",
    icon: "🏷️",
  },
  {
    title: "Clientes e histórico",
    description: "Cadastro completo de clientes com histórico de compras e relacionamento.",
    icon: "👥",
  },
  {
    title: "Vendas flexíveis",
    description: "Múltiplos itens, múltiplas formas de pagamento: dinheiro, PIX, cartão.",
    icon: "💳",
  },
  {
    title: "Validação e troco",
    description: "Validação de quitação do pagamento e cálculo automático de troco.",
    icon: "✅",
  },
  {
    title: "Relatórios centralizados",
    description: "Vendas por período, produtos mais vendidos, ranking de clientes, estoque baixo.",
    icon: "📊",
  },
  {
    title: "Exportação",
    description: "Exporte relatórios em Excel e PDF para análise externa.",
    icon: "📤",
  },
  {
    title: "Backup",
    description: "Backup local e em nuvem para segurança dos seus dados.",
    icon: "☁️",
  },
  {
    title: "Modo offline",
    description: "Opere sem internet e sincronize automaticamente quando voltar.",
    icon: "📡",
  },
  {
    title: "Tipos de usuário",
    description: "Controle por programador, administrador e vendedor.",
    icon: "🔐",
  },
  {
    title: "Permissões",
    description: "Permissões configuráveis por usuário e por tela.",
    icon: "🛡️",
  },
  {
    title: "Gestão de dispositivos",
    description: "Visão admin para dispositivos ativados na conta.",
    icon: "📱",
  },
  {
    title: "Integrações",
    description: "WhatsApp, Telegram e Instagram.",
    badge: "Em breve",
    icon: "🔗",
  },
];

export function FeaturesGrid() {
  return (
    <section
      id="funcionalidades"
      className="py-20 px-4 sm:px-6 lg:px-8 bg-graphite-900/50"
      aria-labelledby="features-title"
    >
      <div className="max-w-6xl mx-auto">
        <h2 id="features-title" className="text-3xl sm:text-4xl font-bold text-white text-center mb-4">
          Funcionalidades
        </h2>
        <p className="text-gray-400 text-center mb-12 max-w-2xl mx-auto">
          Tudo que você precisa para gerenciar sua loja com eficiência
        </p>
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((feature, index) => (
            <article
              key={index}
              className="p-6 rounded-2xl bg-graphite-800/80 border border-graphite-700 hover:border-silver-500/30 transition-colors shadow-soft"
            >
              <div className="flex items-start gap-4">
                <span className="text-2xl" aria-hidden="true">{feature.icon}</span>
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="text-lg font-semibold text-white">{feature.title}</h3>
                    {feature.badge && (
                      <span className="px-2 py-0.5 text-xs font-medium bg-accent-blue/20 text-accent-blue rounded-full">
                        {feature.badge}
                      </span>
                    )}
                  </div>
                  <p className="mt-2 text-gray-400 text-sm leading-relaxed">{feature.description}</p>
                </div>
              </div>
            </article>
          ))}
        </div>
        <div className="mt-10 text-center">
          <a
            href="/funcionalidades"
            className="inline-flex items-center gap-2 text-accent-blue hover:text-accent-blue-light font-medium"
          >
            Ver todas as funcionalidades
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </a>
        </div>
      </div>
    </section>
  );
}
