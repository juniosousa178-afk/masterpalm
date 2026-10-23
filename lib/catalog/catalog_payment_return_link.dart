// Retorno do Mercado Pago para o catálogo público.
//
// O checkout do catálogo envia `back_urls` que apontam para a própria loja:
// `/loja/{loja}?pagamento={sucesso|pendente|falha}`. O retorno é só UX: quem confirma o
// pagamento, cria a venda, baixa estoque e envia confirmações é o webhook (`mpWebhook`).
//
// Preferências criadas antes desta mudança voltam por `/pagamento/{status}?loja={lojaId}`;
// o boot web as reescreve para a rota da loja antes de montar qualquer app, porque o
// [MyApp] administrativo levaria o cliente para o login. Nos dois formatos o boot já deixa a
// barra de endereço em `/loja/{loja}` limpa e o catálogo lê o status por [takePendingFor].

enum CatalogPaymentReturnStatus { sucesso, pendente, falha }

class CatalogPaymentReturn {
  const CatalogPaymentReturn({
    required this.storeRef,
    required this.status,
    required this.approvedByRedirect,
  });

  /// Segmento `{loja}` de `/loja/{loja}` para onde o pagamento voltou.
  final String storeRef;

  /// Status de UX derivado do retorno (nunca autoridade de pagamento).
  final CatalogPaymentReturnStatus status;

  /// `collection_status`/`status` = approved na URL de retorno. Só decide limpar o
  /// carrinho local da loja; não marca pagamento, venda nem estoque.
  final bool approvedByRedirect;

  bool get clearsCart =>
      status == CatalogPaymentReturnStatus.sucesso && approvedByRedirect;

  @override
  bool operator ==(Object other) =>
      other is CatalogPaymentReturn &&
      other.storeRef == storeRef &&
      other.status == status &&
      other.approvedByRedirect == approvedByRedirect;

  @override
  int get hashCode => Object.hash(storeRef, status, approvedByRedirect);

  @override
  String toString() =>
      'CatalogPaymentReturn($storeRef, $status, approved=$approvedByRedirect)';
}

class CatalogPaymentReturnLink {
  CatalogPaymentReturnLink._();

  static const String queryKey = 'pagamento';

  /// Parâmetros que o Mercado Pago acrescenta à `back_url`, removidos da barra de endereço.
  static const Set<String> mpReturnQueryKeys = {
    'collection_id',
    'collection_status',
    'payment_id',
    'status',
    'external_reference',
    'payment_type',
    'merchant_order_id',
    'preference_id',
    'site_id',
    'processing_mode',
    'merchant_account_id',
  };

  static final RegExp _storeRefPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static const String _placeholderStoreRef = 'minha-loja';

  static const Map<CatalogPaymentReturnStatus, String> _statusQuery = {
    CatalogPaymentReturnStatus.sucesso: 'sucesso',
    CatalogPaymentReturnStatus.pendente: 'pendente',
    CatalogPaymentReturnStatus.falha: 'falha',
  };

  static bool _isUsableStoreRef(String? ref) =>
      ref != null &&
      _storeRefPattern.hasMatch(ref) &&
      ref.toLowerCase() != _placeholderStoreRef;

  static String? _lojaPathSegment(Uri uri) {
    final s = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (s.length < 2 || s.first != 'loja') return null;
    return s[1].trim();
  }

  /// Identificador da loja usado na volta: o mesmo segmento `/loja/{x}` em que o cliente
  /// está comprando; fora dessa rota (ex.: domínio próprio na raiz), o [lojaId] canônico.
  static String storeRefForReturn({
    required Uri currentUri,
    required String lojaId,
  }) {
    final seg = _lojaPathSegment(currentUri);
    if (_isUsableStoreRef(seg)) return seg!;
    return lojaId.trim();
  }

  static Uri catalogReturnUri({
    required String storeRef,
    required CatalogPaymentReturnStatus status,
    Map<String, String> extraQuery = const {},
  }) {
    return Uri.parse('/loja/${Uri.encodeComponent(storeRef)}').replace(
      queryParameters: {...extraQuery, queryKey: _statusQuery[status]!},
    );
  }

  /// `back_urls` do checkout Pro para compras do catálogo público.
  static Map<String, String> backUrls({
    required String origin,
    required String storeRef,
  }) {
    String url(CatalogPaymentReturnStatus s) =>
        '$origin${catalogReturnUri(storeRef: storeRef, status: s)}';
    return {
      'success': url(CatalogPaymentReturnStatus.sucesso),
      'failure': url(CatalogPaymentReturnStatus.falha),
      'pending': url(CatalogPaymentReturnStatus.pendente),
    };
  }

  static CatalogPaymentReturnStatus? _parseStatus(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'sucesso':
        return CatalogPaymentReturnStatus.sucesso;
      case 'pendente':
        return CatalogPaymentReturnStatus.pendente;
      case 'falha':
        return CatalogPaymentReturnStatus.falha;
    }
    return null;
  }

  static const Set<String> _mpPendingStatuses = {
    'pending',
    'in_process',
    'in_mediation',
  };

  /// Retorno de pagamento em `/loja/{x}?pagamento=...`; `null` em qualquer outra URL.
  static CatalogPaymentReturn? parse(Uri uri) {
    final storeRef = _lojaPathSegment(uri);
    if (storeRef == null || storeRef.isEmpty) return null;
    final declared = _parseStatus(uri.queryParameters[queryKey]);
    if (declared == null) return null;
    final cs = (uri.queryParameters['collection_status'] ?? '').trim().toLowerCase();
    final ps = (uri.queryParameters['status'] ?? '').trim().toLowerCase();
    final approved = cs == 'approved' || ps == 'approved';
    final mpPending = _mpPendingStatuses.contains(cs) || _mpPendingStatuses.contains(ps);
    final status = declared == CatalogPaymentReturnStatus.sucesso && mpPending && !approved
        ? CatalogPaymentReturnStatus.pendente
        : declared;
    return CatalogPaymentReturn(
      storeRef: storeRef,
      status: status,
      approvedByRedirect: approved,
    );
  }

  static CatalogPaymentReturn? _pending;

  /// Consome o retorno da URL inicial do web (formato novo ou `/pagamento/*` antigo):
  /// guarda o status para o catálogo e devolve a URL limpa da loja, que deve substituir a
  /// atual antes do motor web registrar o histórico — senão a entrada de origem guarda
  /// `?pagamento=` e Voltar/Avançar reaplicaria o retorno.
  static String? consumeInitialUri(Uri uri) {
    final legacy = legacyReturnTarget(uri);
    final target = legacy == null ? uri : uri.resolveUri(legacy);
    final ret = parse(target);
    if (ret == null) return null;
    _pending = ret;
    return cleanedRelativeUrl(target);
  }

  /// Entrega (uma única vez) o retorno pendente se ele pertence a [lojaRef].
  static CatalogPaymentReturn? takePendingFor(String lojaRef) {
    final p = _pending;
    if (p == null || p.storeRef != lojaRef.trim()) return null;
    _pending = null;
    return p;
  }

  static void debugResetPending() => _pending = null;

  static const Map<String, CatalogPaymentReturnStatus> _legacyPaths = {
    '/pagamento/sucesso': CatalogPaymentReturnStatus.sucesso,
    '/pagamento/pendente': CatalogPaymentReturnStatus.pendente,
    '/pagamento/falha': CatalogPaymentReturnStatus.falha,
  };

  /// Rota da loja para um retorno antigo `/pagamento/{status}?loja={lojaId}` do catálogo.
  /// `null` para retornos de plano (`plano=`), sem loja ou com loja inválida.
  static Uri? legacyReturnTarget(Uri uri) {
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
    final status = _legacyPaths[path];
    if (status == null) return null;
    if ((uri.queryParameters['plano'] ?? '').trim().isNotEmpty) return null;
    final loja = (uri.queryParameters['loja'] ?? '').trim();
    if (!_isUsableStoreRef(loja)) return null;
    final rest = Map<String, String>.from(uri.queryParameters)..remove('loja');
    return catalogReturnUri(storeRef: loja, status: status, extraQuery: rest);
  }

  /// URL relativa sem o marcador de retorno nem os parâmetros do Mercado Pago,
  /// preservando a rota da loja e os demais parâmetros do catálogo.
  static String cleanedRelativeUrl(Uri uri) {
    final qp = Map<String, String>.from(uri.queryParameters)
      ..remove(queryKey)
      ..removeWhere((k, _) => mpReturnQueryKeys.contains(k));
    final query = qp.isEmpty ? '' : '?${Uri(queryParameters: qp).query}';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '$path$query$fragment';
  }

  static String message(CatalogPaymentReturnStatus status) {
    switch (status) {
      case CatalogPaymentReturnStatus.sucesso:
        return 'Pagamento recebido. Estamos confirmando seu pedido.';
      case CatalogPaymentReturnStatus.pendente:
        return 'Pagamento em processamento. Seu pedido será confirmado quando o pagamento for aprovado.';
      case CatalogPaymentReturnStatus.falha:
        return 'Pagamento não concluído. Seus itens continuam no carrinho.';
    }
  }
}
