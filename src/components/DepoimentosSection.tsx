const depoimentos = [
  {
    nome: "Maria Silva",
    cargo: "Proprietária de loja de semijoias",
    texto: "O MasterPalm transformou a gestão da minha loja. Consigo controlar estoque, vendas e clientes em um só lugar, mesmo sem internet.",
    avatar: "M",
  },
  {
    nome: "João Santos",
    cargo: "Gerente de varejo",
    texto: "Sistema completo e intuitivo. Os relatórios em Excel e PDF facilitam muito a análise e o planejamento do negócio.",
    avatar: "J",
  },
  {
    nome: "Ana Costa",
    cargo: "Administradora",
    texto: "A flexibilidade de usar no celular e no computador é excelente. O modo offline salva quando a conexão falha.",
    avatar: "A",
  },
];

export function DepoimentosSection() {
  return (
    <section
      className="py-20 px-4 sm:px-6 lg:px-8 bg-graphite-900/50"
      aria-labelledby="depoimentos-title"
    >
      <div className="max-w-6xl mx-auto">
        <h2 id="depoimentos-title" className="text-3xl sm:text-4xl font-bold text-white text-center mb-4">
          Depoimentos
        </h2>
        <p className="text-gray-400 text-center mb-12 max-w-2xl mx-auto">
          O que nossos usuários dizem sobre o MasterPalm
        </p>

        <div className="grid sm:grid-cols-3 gap-6">
          {depoimentos.map((dep, index) => (
            <article
              key={index}
              className="p-6 rounded-2xl bg-graphite-800/80 border border-graphite-700"
            >
              <div className="flex items-center gap-4 mb-4">
                <div className="w-12 h-12 rounded-full bg-accent-blue/20 flex items-center justify-center text-accent-blue font-bold">
                  {dep.avatar}
                </div>
                <div>
                  <p className="font-semibold text-white">{dep.nome}</p>
                  <p className="text-sm text-gray-500">{dep.cargo}</p>
                </div>
              </div>
              <p className="text-gray-400 text-sm leading-relaxed italic">&ldquo;{dep.texto}&rdquo;</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
