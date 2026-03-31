// Conteúdo da página "Sobre a loja" no catálogo público (cfg['sobreLojaCatalogo']).

class CatalogSobreLojaConfig {
  final String titulo;
  final String subtitulo;
  final String bannerUrl;
  final String introducao;
  final String missao;
  final String visao;
  final String valores;
  final List<String> destaques;
  final String endereco;
  final String horarioAtendimento;
  final String emailContato;
  final bool mostrarDadosLegais;
  /// URL opcional (site institucional); botão na página.
  final String linkExternoUrl;

  const CatalogSobreLojaConfig({
    this.titulo = '',
    this.subtitulo = '',
    this.bannerUrl = '',
    this.introducao = '',
    this.missao = '',
    this.visao = '',
    this.valores = '',
    this.destaques = const [],
    this.endereco = '',
    this.horarioAtendimento = '',
    this.emailContato = '',
    this.mostrarDadosLegais = true,
    this.linkExternoUrl = '',
  });

  static CatalogSobreLojaConfig fromCfg(Map<String, dynamic> cfg) {
    final raw = cfg['sobreLojaCatalogo'];
    if (raw is! Map) return const CatalogSobreLojaConfig();
    final m = raw.map((k, v) => MapEntry(k.toString(), v));

    List<String> parseDestaques(dynamic d) {
      if (d is List) {
        return d
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    var linkEx =
        (m['linkExternoUrl'] ?? m['linkExterno'] ?? '').toString().trim();
    if (linkEx.isEmpty) {
      final rp = cfg['rodape'];
      if (rp is Map) {
        final s = (rp['sobre'] ?? '').toString().trim();
        final low = s.toLowerCase();
        if (low.startsWith('http://') || low.startsWith('https://')) {
          linkEx = s;
        }
      }
    }

    return CatalogSobreLojaConfig(
      titulo: (m['titulo'] ?? '').toString().trim(),
      subtitulo: (m['subtitulo'] ?? '').toString().trim(),
      bannerUrl: (m['bannerUrl'] ?? m['banner_url'] ?? '').toString().trim(),
      introducao: (m['introducao'] ?? m['texto'] ?? '').toString().trim(),
      missao: (m['missao'] ?? '').toString().trim(),
      visao: (m['visao'] ?? '').toString().trim(),
      valores: (m['valores'] ?? '').toString().trim(),
      destaques: parseDestaques(m['destaques']),
      endereco: (m['endereco'] ?? '').toString().trim(),
      horarioAtendimento:
          (m['horarioAtendimento'] ?? m['horario'] ?? '').toString().trim(),
      emailContato: (m['emailContato'] ?? m['email'] ?? '').toString().trim(),
      mostrarDadosLegais: m['mostrarDadosLegais'] != false,
      linkExternoUrl: linkEx,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'titulo': titulo,
      'subtitulo': subtitulo,
      'bannerUrl': bannerUrl,
      'introducao': introducao,
      'missao': missao,
      'visao': visao,
      'valores': valores,
      'destaques': destaques,
      'endereco': endereco,
      'horarioAtendimento': horarioAtendimento,
      'emailContato': emailContato,
      'mostrarDadosLegais': mostrarDadosLegais,
      'linkExternoUrl': linkExternoUrl,
    };
  }

  /// Há conteúdo além do padrão (para decidir textos de apoio na tela).
  bool get temConteudoBasico =>
      introducao.isNotEmpty ||
      missao.isNotEmpty ||
      visao.isNotEmpty ||
      valores.isNotEmpty ||
      bannerUrl.isNotEmpty ||
      subtitulo.isNotEmpty ||
      destaques.isNotEmpty;
}
