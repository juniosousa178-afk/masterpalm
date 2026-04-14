import '../catalog/domain/catalog_custom_domain.dart';
import '../models/domain_provider_guide.dart';

const String _kTarget = kCatalogPublicCnameTarget;
const String _kName = kCatalogDnsRecordName;

final List<DomainProviderGuide> kDomainProviderGuides = [
  DomainProviderGuide(
    id: 'registro_br',
    title: 'Registro.br',
    shortDescription:
        'Painel oficial de domínios .br — zona DNS no próprio Registro.br ou delegada.',
    steps: [
      'Acesse https://registro.br e faça login na sua conta.',
      'Abra a lista de domínios e clique no domínio desejado (zona onde o catálogo será publicado).',
      'Localize a área de DNS ou “Zona DNS”.',
      'Se ainda não estiver ativa, use “Configurar zona DNS” ou equivalente.',
      'Se o provedor oferecer modo simples e avançado, prefira o modo que permita criar registro CNAME.',
      'Adicione uma nova entrada do tipo CNAME.',
      'No campo de nome (ou “host”), informe: $_kName',
      'No destino (ou “dados” / “valor”), informe exatamente: $_kTarget',
      'Salve ou confirme as alterações na zona.',
      'Aguarde a propagação e use “Verificar novamente” no app apenas como lembrete — a confirmação técnica completa ainda depende da infraestrutura.',
    ],
    notes: [
      'Se o domínio estiver delegado a outro provedor (DNS na Cloudflare, por exemplo), faça o CNAME lá, não no Registro.br.',
      'Não crie outro registro com o mesmo nome $_kName que conflite (ex.: outro CNAME ou A no mesmo host).',
    ],
  ),
  DomainProviderGuide(
    id: 'cloudflare',
    title: 'Cloudflare',
    shortDescription:
        'DNS rápido e painel em inglês/português — ideal para proxy e gestão de registros.',
    steps: [
      'Acesse https://dash.cloudflare.com e faça login.',
      'Selecione o domínio (site) correto.',
      'Vá em DNS → Records (Registros).',
      'Clique em Add record (Adicionar registro).',
      'Tipo: CNAME.',
      'Name (Nome): $_kName',
      'Target (Destino): $_kTarget',
      'Proxy status: desligado — use “DNS only” (somente DNS), não o proxy laranja, para este apontamento.',
      'Salve o registro.',
      'Aguarde a propagação. O painel da Cloudflare costuma aplicar na hora, mas resolvers no mundo ainda podem demorar.',
    ],
    notes: [
      'Se você já usa Cloudflare como proxy para o site principal, o subdomínio do catálogo continua sendo um CNAME separado com “DNS only”.',
      'Evite duplicar um registro A com o mesmo nome $_kName.',
    ],
  ),
  DomainProviderGuide(
    id: 'hostinger',
    title: 'Hostinger',
    shortDescription: 'Hospedagem compartilhada e DNS no hPanel.',
    steps: [
      'Acesse https://www.hostinger.com.br e faça login no hPanel.',
      'Abra Domínios e selecione o domínio.',
      'Entre em Zona DNS ou Gerenciar registros DNS.',
      'Adicione um novo registro do tipo CNAME.',
      'Nome / Host: $_kName',
      'Destino / Aponta para: $_kTarget',
      'TTL: use o padrão ou “Automático”, se disponível.',
      'Salve o registro e confira se não há outro registro com o mesmo nome.',
      'Aguarde a propagação antes de testar o endereço no navegador.',
    ],
    notes: [
      'A nomenclatura exata dos botões pode variar levemente na interface, mas o tipo de registro deve ser CNAME.',
    ],
  ),
  DomainProviderGuide(
    id: 'hostgator',
    title: 'HostGator',
    shortDescription: 'cPanel clássico com editor de zona avançada.',
    steps: [
      'Acesse o portal da HostGator e abra o cPanel do domínio.',
      'Procure por “Zone Editor”, “Editor de Zona” ou “DNS avançado”.',
      'Escolha adicionar um registro CNAME.',
      'Nome (ou host relativo): $_kName',
      'Destino (CNAME): $_kTarget',
      'Salve o registro.',
      'Se o cPanel listar o domínio completo, confira se o nome final ficará como $_kName.seudominio...',
      'Aguarde a propagação DNS.',
    ],
    notes: [
      'Em alguns planos, alterações DNS passam por validação adicional; verifique e-mails de confirmação da hospedagem.',
    ],
  ),
  DomainProviderGuide(
    id: 'godaddy',
    title: 'GoDaddy',
    shortDescription: 'Gerenciador de DNS da GoDaddy (EUA) com interface em português.',
    steps: [
      'Acesse https://www.godaddy.com e faça login.',
      'Vá em Meus produtos → Domínios e abra o domínio.',
      'Abra Gerenciar DNS ou Registros DNS.',
      'Clique em Adicionar ou Add.',
      'Tipo: CNAME.',
      'Nome / Host: $_kName',
      'Valor / Destino: $_kTarget',
      'TTL: padrão (geralmente 1 hora).',
      'Salve e confira a lista de registros para conflitos no mesmo host.',
      'Aguarde a propagação.',
    ],
    notes: [
      'Se o domínio usar nameservers de outro provedor, o DNS deve ser editado onde os nameservers apontam, não na GoDaddy.',
    ],
  ),
  DomainProviderGuide(
    id: 'locaweb',
    title: 'Locaweb',
    shortDescription: 'Painel brasileiro comum em PMEs.',
    steps: [
      'Acesse o site da Locaweb e faça login no painel do cliente.',
      'Abra a gestão do domínio ou DNS associado ao seu plano.',
      'Localize a zona DNS ou “Gerenciar DNS”.',
      'Inclua um registro do tipo CNAME.',
      'Nome / host: $_kName',
      'Destino: $_kTarget',
      'Salve as alterações.',
      'Verifique se o painel mostra o registro como ativo e sem erro de sintaxe.',
      'Aguarde a propagação.',
    ],
    notes: [
      'Em contas antigas, o caminho no menu pode ser “DNS” ou “Apontamentos”; o importante é criar um CNAME.',
    ],
  ),
  DomainProviderGuide(
    id: 'umbler',
    title: 'Umbler',
    shortDescription: 'Hospedagem e DNS com foco em simplicidade.',
    steps: [
      'Acesse https://www.umbler.com e faça login.',
      'Abra o site ou domínio correspondente.',
      'Vá até a seção de DNS ou registros.',
      'Adicione um CNAME.',
      'Nome: $_kName',
      'Destino: $_kTarget',
      'Salve e confira a lista de registros.',
      'Aguarde a propagação.',
    ],
    notes: [
      'Se o domínio estiver apenas registrado e o DNS em outro lugar, use o painel onde os nameservers estão configurados.',
    ],
  ),
  DomainProviderGuide(
    id: 'outros',
    title: 'Outros provedores',
    shortDescription:
        'Passo a passo genérico para qualquer painel que permita editar DNS.',
    steps: [
      'Faça login no painel onde o DNS do seu domínio é administrado (onde estão os nameservers).',
      'Localize a seção “DNS”, “Zona DNS”, “Registros” ou “Apontamentos”.',
      'Crie um novo registro do tipo CNAME.',
      'No nome (host), use: $_kName',
      'No valor ou destino, use exatamente: $_kTarget',
      'Salve o registro e confira se não há outro registro com o mesmo nome.',
      'Aguarde a propagação e teste depois em um navegador ou ferramenta de DNS externa, se desejar.',
    ],
    notes: [
      'Se não encontrar a opção CNAME, confirme se o domínio não está bloqueado por plano ou se o DNS não está delegado a outro serviço.',
      'O app não altera DNS por você: tudo é feito manualmente no provedor, por segurança e controle do lojista.',
    ],
  ),
];

DomainProviderGuide? guideByProviderId(String id) {
  for (final g in kDomainProviderGuides) {
    if (g.id == id) return g;
  }
  return null;
}
