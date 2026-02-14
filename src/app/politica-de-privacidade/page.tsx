import type { Metadata } from "next";
import Link from "next/link";
import { siteConfig } from "@/config/site";

export const metadata: Metadata = {
  title: "Política de Privacidade",
  description: "Política de Privacidade do MasterPalm - Conheça como tratamos seus dados em conformidade com a LGPD.",
};

export default function PoliticaPrivacidadePage() {
  const vigencia = new Date().toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "long",
    year: "numeric",
  });

  return (
    <div className="pt-24 pb-20 px-4 sm:px-6 lg:px-8">
      <div className="max-w-3xl mx-auto prose prose-invert prose-gray">
        <h1 className="text-3xl sm:text-4xl font-bold text-white mb-8">
          Política de Privacidade
        </h1>

        <p className="text-gray-400 text-sm mb-8">
          <strong>Data de vigência:</strong> {vigencia}
        </p>

        <div className="space-y-8 text-gray-400 text-sm leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold text-white mb-4">1. Introdução</h2>
            <p>
              Esta Política de Privacidade descreve como o MasterPalm (&quot;nós&quot;, &quot;nosso&quot; ou &quot;sistema&quot;) coleta, usa, armazena e protege os dados dos usuários, em conformidade com a Lei Geral de Proteção de Dados (LGPD - Lei nº 13.709/2018).
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">2. Dados que podem ser tratados</h2>
            <p>Podemos tratar os seguintes tipos de dados:</p>
            <ul className="list-disc list-inside space-y-2 mt-2">
              <li><strong className="text-gray-300">Dados de conta/login:</strong> e-mail, identificador único (uid) e informações de autenticação, quando houver sistema de login.</li>
              <li><strong className="text-gray-300">Dados operacionais:</strong> produtos, clientes, vendas, estoque e demais informações inseridas pelo usuário no sistema.</li>
              <li><strong className="text-gray-300">Dados técnicos de diagnóstico:</strong> informações de crash e erros (ex.: Crashlytics), quando aplicável.</li>
              <li><strong className="text-gray-300">Métricas de uso:</strong> dados de Analytics para melhoria do produto, quando aplicável.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">3. Finalidades do tratamento</h2>
            <p>Os dados são tratados para:</p>
            <ul className="list-disc list-inside space-y-2 mt-2">
              <li>Operação do sistema e prestação dos serviços</li>
              <li>Sincronização de dados entre dispositivos e em nuvem</li>
              <li>Segurança e prevenção de fraudes</li>
              <li>Suporte técnico e atendimento ao usuário</li>
              <li>Melhoria contínua do produto</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">4. Armazenamento</h2>
            <p>
              Os dados podem ser armazenados localmente no dispositivo (modo offline) e em nuvem, quando o usuário habilitar backup ou sincronização. A sincronização ocorre conforme as configurações escolhidas pelo usuário.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">5. Compartilhamento</h2>
            <p>
              Podemos compartilhar dados com provedores de infraestrutura (ex.: Google/Firebase) necessários à operação do sistema. Esses provedores são contratados com obrigações de confidencialidade e proteção de dados. Não vendemos dados pessoais a terceiros.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">6. Retenção e exclusão</h2>
            <p>
              Os dados são mantidos enquanto o usuário utilizar o sistema e conforme exigências legais. Para solicitar exclusão, portabilidade ou correção de dados, entre em contato pelo e-mail: <a href={`mailto:${siteConfig.SUPPORT_EMAIL}`} className="text-accent-blue hover:underline">{siteConfig.SUPPORT_EMAIL}</a>.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">7. Direitos do titular (LGPD)</h2>
            <p>Em conformidade com a LGPD, você tem direito a:</p>
            <ul className="list-disc list-inside space-y-2 mt-2">
              <li>Confirmação da existência de tratamento</li>
              <li>Acesso aos dados</li>
              <li>Correção de dados incompletos ou desatualizados</li>
              <li>Anonimização, bloqueio ou eliminação de dados desnecessários</li>
              <li>Portabilidade dos dados</li>
              <li>Revogação do consentimento</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">8. Contato do encarregado</h2>
            <p>
              Para exercer seus direitos ou esclarecer dúvidas sobre esta política, entre em contato: <a href={`mailto:${siteConfig.SUPPORT_EMAIL}`} className="text-accent-blue hover:underline">{siteConfig.SUPPORT_EMAIL}</a>.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">9. Alterações</h2>
            <p>
              Esta política pode ser atualizada. Alterações significativas serão comunicadas por meio do sistema ou por e-mail. A data de vigência indicada no início deste documento reflete a última atualização.
            </p>
          </section>
        </div>

        <div className="mt-12">
          <Link href="/" className="text-accent-blue hover:text-accent-blue-light font-medium">
            ← Voltar para a página inicial
          </Link>
        </div>
      </div>
    </div>
  );
}
