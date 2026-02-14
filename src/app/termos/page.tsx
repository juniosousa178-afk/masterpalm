import type { Metadata } from "next";
import Link from "next/link";
import { siteConfig } from "@/config/site";

export const metadata: Metadata = {
  title: "Termos de Uso",
  description: "Termos de Uso do MasterPalm - Condições de utilização do sistema.",
};

export default function TermosPage() {
  return (
    <div className="pt-24 pb-20 px-4 sm:px-6 lg:px-8">
      <div className="max-w-3xl mx-auto prose prose-invert prose-gray">
        <h1 className="text-3xl sm:text-4xl font-bold text-white mb-8">
          Termos de Uso
        </h1>

        <div className="space-y-8 text-gray-400 text-sm leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold text-white mb-4">1. Aceitação</h2>
            <p>
              Ao utilizar o MasterPalm (APK ou AppWeb), você concorda com estes Termos de Uso. Se não concordar, não utilize o sistema.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">2. Uso permitido</h2>
            <p>
              O MasterPalm destina-se ao controle de estoque, vendas, clientes e relatórios de negócios. O uso deve ser lícito, ético e em conformidade com a legislação aplicável. É proibido utilizar o sistema para fins ilegais, fraudulentos ou que violem direitos de terceiros.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">3. Responsabilidade pelos dados</h2>
            <p>
              O usuário é responsável pela veracidade e legalidade dos dados inseridos no sistema. Recomendamos a realização de backups regulares. O MasterPalm não se responsabiliza por perda de dados decorrente de falhas do usuário, de dispositivos ou de terceiros fora de nosso controle.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">4. Proibição de abuso</h2>
            <p>
              É proibido: tentar acessar áreas restritas do sistema sem autorização; realizar engenharia reversa; distribuir versões modificadas do software; usar o sistema para sobrecarregar servidores ou prejudicar outros usuários; ou praticar qualquer ato que comprometa a segurança ou a integridade do serviço.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">5. Disponibilidade &quot;como está&quot;</h2>
            <p>
              O MasterPalm é oferecido &quot;como está&quot;. Fazemos esforços para manter a disponibilidade e a qualidade do serviço, mas não garantimos disponibilidade ininterrupta. Atualizações podem ser aplicadas periodicamente para correções e melhorias.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">6. Limites de responsabilidade</h2>
            <p>
              Na medida permitida pela lei, o MasterPalm não se responsabiliza por danos indiretos, incidentais ou consequenciais decorrentes do uso ou da impossibilidade de uso do sistema. A responsabilidade total, quando aplicável, limita-se ao valor efetivamente pago pelo usuário nos últimos 12 meses, quando houver cobrança.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">7. Suporte e contato</h2>
            <p>
              Para suporte técnico, dúvidas ou reclamações, entre em contato: <a href={`mailto:${siteConfig.SUPPORT_EMAIL}`} className="text-accent-blue hover:underline">{siteConfig.SUPPORT_EMAIL}</a> ou pelo WhatsApp indicado no site.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-4">8. Alterações</h2>
            <p>
              Estes Termos podem ser alterados a qualquer momento. Alterações significativas serão comunicadas. O uso continuado do sistema após as alterações constitui aceitação dos novos termos.
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
