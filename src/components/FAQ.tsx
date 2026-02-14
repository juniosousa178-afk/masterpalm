"use client";

import { useState } from "react";

const faqs = [
  {
    question: "O MasterPalm funciona offline?",
    answer: "Sim. O APK para Android opera em modo offline e sincroniza automaticamente os dados quando a conexão com a internet for restabelecida. O AppWeb requer conexão para funcionar.",
  },
  {
    question: "Posso usar em mais de um dispositivo?",
    answer: "Sim. Você pode instalar o APK em vários dispositivos Android e acessar o AppWeb em qualquer navegador. A gestão de dispositivos ativados está disponível na visão de administrador.",
  },
  {
    question: "Como faço backup dos meus dados?",
    answer: "O MasterPalm oferece backup local e em nuvem. Você pode configurar backups automáticos e exportar relatórios em Excel e PDF para manter cópias adicionais.",
  },
  {
    question: "Quais formas de pagamento são suportadas nas vendas?",
    answer: "O sistema suporta dinheiro, PIX e cartão. Cada venda pode ter múltiplos itens e múltiplas formas de pagamento, com validação de quitação e cálculo automático de troco.",
  },
  {
    question: "Como instalo o APK no Android?",
    answer: "Baixe o arquivo APK pelo link oficial, permita a instalação de apps de fontes desconhecidas nas configurações do Android (necessário apenas para este tipo de instalação) e toque no arquivo para instalar. Consulte a página de download para instruções detalhadas.",
  },
  {
    question: "O sistema é seguro?",
    answer: "Sim. Baixe o APK apenas pelo link oficial do site. Os dados são armazenados de forma segura e o sistema segue boas práticas de proteção. Consulte nossa Política de Privacidade para mais detalhes.",
  },
];

export function FAQ() {
  const [openIndex, setOpenIndex] = useState<number | null>(0);

  return (
    <section
      id="faq"
      className="py-20 px-4 sm:px-6 lg:px-8 bg-graphite-900/50"
      aria-labelledby="faq-title"
    >
      <div className="max-w-3xl mx-auto">
        <h2 id="faq-title" className="text-3xl sm:text-4xl font-bold text-white text-center mb-4">
          Perguntas Frequentes
        </h2>
        <p className="text-gray-400 text-center mb-12">
          Tire suas dúvidas sobre o MasterPalm
        </p>

        <div className="space-y-4">
          {faqs.map((faq, index) => (
            <div
              key={index}
              className="rounded-xl bg-graphite-800/80 border border-graphite-700 overflow-hidden"
            >
              <button
                type="button"
                className="w-full px-6 py-4 text-left flex items-center justify-between gap-4 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-blue"
                onClick={() => setOpenIndex(openIndex === index ? null : index)}
                aria-expanded={openIndex === index}
                aria-controls={`faq-answer-${index}`}
                id={`faq-question-${index}`}
              >
                <span className="font-medium text-white">{faq.question}</span>
                <svg
                  className={`w-5 h-5 text-gray-400 flex-shrink-0 transition-transform ${openIndex === index ? "rotate-180" : ""}`}
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </button>
              <div
                id={`faq-answer-${index}`}
                role="region"
                aria-labelledby={`faq-question-${index}`}
                className={`overflow-hidden transition-all ${openIndex === index ? "max-h-96" : "max-h-0"}`}
              >
                <div className="px-6 pb-4 text-gray-400 text-sm leading-relaxed">
                  {faq.answer}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
