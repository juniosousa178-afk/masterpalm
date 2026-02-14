import type { Metadata } from "next";
import Link from "next/link";
import { siteConfig } from "@/config/site";

export const metadata: Metadata = {
  title: "Funcionalidades",
  description: "Conheça todas as funcionalidades do MasterPalm: estoque, vendas, clientes, relatórios e muito mais.",
};

const features = [
  {
    title: "Controle de estoque com baixa automática em vendas",
    description: "O estoque é atualizado automaticamente a cada venda realizada. Configure alertas para produtos com estoque baixo e mantenha o inventário sempre em dia.",
  },
  {
    title: "Cadastro de produtos com variações (tamanho, cor)",
    description: "Cadastre produtos com múltiplas variações como tamanho, cor e outras opções. Ideal para lojas de roupas, semijoias e itens com variações.",
  },
  {
    title: "Cadastro de clientes e histórico completo",
    description: "Mantenha um cadastro completo de clientes com dados de contato e histórico de todas as compras realizadas.",
  },
  {
    title: "Vendas com múltiplos itens e múltiplas formas de pagamento",
    description: "Registre vendas com vários produtos e aceite dinheiro, PIX e cartão na mesma transação.",
  },
  {
    title: "Validação de quitação do pagamento e cálculo de troco",
    description: "O sistema valida se o pagamento foi quitado e calcula o troco automaticamente.",
  },
  {
    title: "Relatórios centralizados",
    description: "Vendas por período, produtos mais vendidos, ranking de clientes, estoque baixo e outros relatórios em um só lugar.",
  },
  {
    title: "Exportação de relatórios (Excel e PDF)",
    description: "Exporte seus relatórios em Excel ou PDF para análise externa, contabilidade ou backup.",
  },
  {
    title: "Backup local e em nuvem",
    description: "Faça backup dos seus dados localmente ou na nuvem para garantir a segurança das informações.",
  },
  {
    title: "Modo offline com sincronização",
    description: "Opere sem internet. Quando a conexão voltar, os dados são sincronizados automaticamente.",
  },
  {
    title: "Controle por tipo de usuário",
    description: "Defina perfis de programador, administrador e vendedor com diferentes níveis de acesso.",
  },
  {
    title: "Permissões configuráveis por usuário e por tela",
    description: "Personalize o que cada usuário pode ver e fazer em cada tela do sistema.",
  },
  {
    title: "Gestão de dispositivos ativados",
    description: "Na visão de administrador, gerencie quais dispositivos estão vinculados à conta.",
  },
  {
    title: "Integrações (WhatsApp, Telegram, Instagram)",
    description: "Integração com canais de comunicação para envio de notificações e atendimento.",
    badge: "Em breve",
  },
];

export default function FuncionalidadesPage() {
  return (
    <div className="pt-24 pb-20 px-4 sm:px-6 lg:px-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-3xl sm:text-4xl font-bold text-white mb-4">
          Funcionalidades
        </h1>
        <p className="text-gray-400 mb-12">
          {siteConfig.description}
        </p>

        <div className="space-y-8">
          {features.map((feature, index) => (
            <article
              key={index}
              className="p-6 rounded-2xl bg-graphite-800/80 border border-graphite-700"
            >
              <div className="flex items-start gap-3">
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-xl font-semibold text-white">{feature.title}</h2>
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

        <div className="mt-12 flex gap-4">
          <Link
            href="/download"
            className="inline-flex items-center gap-2 px-6 py-3 bg-accent-blue text-white rounded-xl font-medium hover:bg-accent-blue-light transition-colors"
          >
            Baixar APK
          </Link>
          <a
            href={siteConfig.APP_WEB_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 px-6 py-3 border border-silver-500/50 text-silver-400 rounded-xl font-medium hover:bg-graphite-800 hover:text-white transition-colors"
          >
            Acessar AppWeb
          </a>
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
