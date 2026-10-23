import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_initial_web_route.dart';
import 'package:master_palm/catalog/catalog_payment_return_link.dart';
import 'package:master_palm/catalog/public_order_link.dart';
import 'package:master_palm/config/app_urls.dart';
import 'package:master_palm/features/plans/plan_return_link.dart';

const _origin = 'https://app.mastepalm.com.br';
const _lojaA = 'loja-a';
const _lojaB = 'loja-b';
const _lojaIdA = 'LojaIdAaaaaaaaaaaaaa';

/// Query típica que o Mercado Pago acrescenta à `back_url` (valores fictícios).
Map<String, String> _mpQuery(String status) => {
      'collection_id': '1234567890',
      'collection_status': status,
      'payment_id': '1234567890',
      'status': status,
      'external_reference': 'ref-ficticia',
      'payment_type': 'credit_card',
      'merchant_order_id': '987654321',
      'preference_id': '111-aaa',
      'site_id': 'MLB',
      'processing_mode': 'aggregator',
      'merchant_account_id': 'null',
    };

Uri _mpReturn(String backUrl, String status) {
  final u = Uri.parse(backUrl);
  return u.replace(queryParameters: {...u.queryParameters, ..._mpQuery(status)});
}

CatalogRouteDecision _decide(Uri uri) => CatalogRouteDecision.fromUri(
      uri,
      isDefaultAppOrCatalogHostingHost: AppUrls.isDefaultMasterPalmCatalogHost,
      isPublicMarketingHost: AppUrls.isPublicMarketingHost,
      customDomainMappingResolved: null,
    );

void main() {
  group('backUrls — mesma loja para sucesso, pendente e falha', () {
    test('loja A volta para /loja/loja-a', () {
      final urls = CatalogPaymentReturnLink.backUrls(origin: _origin, storeRef: _lojaA);
      expect(urls, {
        'success': '$_origin/loja/loja-a?pagamento=sucesso',
        'failure': '$_origin/loja/loja-a?pagamento=falha',
        'pending': '$_origin/loja/loja-a?pagamento=pendente',
      });
    });

    test('loja B nunca recebe a URL da loja A', () {
      final a = CatalogPaymentReturnLink.backUrls(origin: _origin, storeRef: _lojaA);
      final b = CatalogPaymentReturnLink.backUrls(origin: _origin, storeRef: _lojaB);
      for (final k in ['success', 'failure', 'pending']) {
        expect(Uri.parse(b[k]!).path, '/loja/loja-b');
        expect(b[k], isNot(contains('loja-a')));
        expect(a[k], isNot(contains('loja-b')));
      }
    });

    test('nenhuma back_url aponta para /pagamento, /login ou /home', () {
      final urls = CatalogPaymentReturnLink.backUrls(origin: _origin, storeRef: _lojaA);
      for (final u in urls.values) {
        final p = Uri.parse(u).path;
        expect(p.startsWith('/pagamento'), isFalse);
        expect(p, isNot('/login'));
        expect(p, isNot('/home'));
      }
    });

    test('back_urls abrem o catálogo público, nunca o app administrativo', () {
      final urls = CatalogPaymentReturnLink.backUrls(origin: _origin, storeRef: _lojaA);
      for (final u in urls.values) {
        final d = _decide(_mpReturn(u, 'approved'));
        expect(d.kind, CatalogInitialRouteKind.publicCatalogByLojaPath);
        expect(d.extractedSlugOrId, _lojaA);
      }
    });
  });

  group('storeRefForReturn — identidade determinística', () {
    test('usa o slug da URL em que o cliente está comprando', () {
      expect(
        CatalogPaymentReturnLink.storeRefForReturn(
          currentUri: Uri.parse('$_origin/loja/loja-a?cat=aneis&page=2'),
          lojaId: _lojaIdA,
        ),
        _lojaA,
      );
    });

    test('fora de /loja (domínio próprio na raiz) usa o lojaId canônico', () {
      expect(
        CatalogPaymentReturnLink.storeRefForReturn(
          currentUri: Uri.parse('https://lojaa.example.com/'),
          lojaId: _lojaIdA,
        ),
        _lojaIdA,
      );
    });

    test('placeholder minha-loja e segmentos inválidos caem no lojaId', () {
      for (final u in [
        '$_origin/loja/minha-loja',
        '$_origin/loja/a%20b',
        '$_origin/loja/',
      ]) {
        expect(
          CatalogPaymentReturnLink.storeRefForReturn(
              currentUri: Uri.parse(u), lojaId: _lojaIdA),
          _lojaIdA,
          reason: u,
        );
      }
    });
  });

  group('parse — status de UX (não é autoridade de pagamento)', () {
    test('sucesso aprovado limpa carrinho', () {
      final r = CatalogPaymentReturnLink.parse(
          _mpReturn('$_origin/loja/loja-a?pagamento=sucesso', 'approved'))!;
      expect(r.status, CatalogPaymentReturnStatus.sucesso);
      expect(r.approvedByRedirect, isTrue);
      expect(r.clearsCart, isTrue);
    });

    test('sucesso sem query do MP mostra mensagem neutra e mantém carrinho', () {
      final r = CatalogPaymentReturnLink.parse(
          Uri.parse('$_origin/loja/loja-a?pagamento=sucesso'))!;
      expect(r.status, CatalogPaymentReturnStatus.sucesso);
      expect(r.clearsCart, isFalse);
    });

    test('sucesso com collection_status pending vira pendente', () {
      for (final s in ['pending', 'in_process']) {
        final r = CatalogPaymentReturnLink.parse(
            _mpReturn('$_origin/loja/loja-a?pagamento=sucesso', s))!;
        expect(r.status, CatalogPaymentReturnStatus.pendente, reason: s);
        expect(r.clearsCart, isFalse);
      }
    });

    test('pendente e falha nunca limpam carrinho', () {
      final p = CatalogPaymentReturnLink.parse(
          _mpReturn('$_origin/loja/loja-a?pagamento=pendente', 'pending'))!;
      expect(p.status, CatalogPaymentReturnStatus.pendente);
      expect(p.clearsCart, isFalse);
      for (final s in ['rejected', 'null', 'cancelled']) {
        final f = CatalogPaymentReturnLink.parse(
            _mpReturn('$_origin/loja/loja-a?pagamento=falha', s))!;
        expect(f.status, CatalogPaymentReturnStatus.falha, reason: s);
        expect(f.clearsCart, isFalse);
      }
    });

    test('falha com status approved forjado continua falha e não limpa carrinho', () {
      final f = CatalogPaymentReturnLink.parse(
          _mpReturn('$_origin/loja/loja-a?pagamento=falha', 'approved'))!;
      expect(f.status, CatalogPaymentReturnStatus.falha);
      expect(f.clearsCart, isFalse);
    });

    test('ignora URLs sem marcador, com status desconhecido ou fora de /loja', () {
      for (final u in [
        '$_origin/loja/loja-a',
        '$_origin/loja/loja-a?pagamento=talvez',
        '$_origin/pagamento/sucesso?loja=loja-a',
        '$_origin/pedido/PedidoAaaaaaaaaaaaaa?loja=loja-a&pagamento=sucesso',
        '$_origin/?pagamento=sucesso',
      ]) {
        expect(CatalogPaymentReturnLink.parse(Uri.parse(u)), isNull, reason: u);
      }
    });
  });

  group('legacyReturnTarget — preferências antigas /pagamento/*?loja=', () {
    test('sucesso, pendente e falha voltam para a mesma loja', () {
      const cases = {
        'sucesso': 'sucesso',
        'pendente': 'pendente',
        'falha': 'falha',
      };
      cases.forEach((path, status) {
        final legacy =
            _mpReturn('$_origin/pagamento/$path?loja=$_lojaIdA', 'approved');
        final t = CatalogPaymentReturnLink.legacyReturnTarget(legacy)!;
        expect(t.path, '/loja/$_lojaIdA');
        expect(t.queryParameters['pagamento'], status);
        expect(t.queryParameters.containsKey('loja'), isFalse);
        expect(t.queryParameters['collection_status'], 'approved');
        expect(t.hasAuthority, isFalse);
      });
    });

    test('alvo reescrito é decidido como catálogo antes de qualquer login', () {
      final legacy = _mpReturn('$_origin/pagamento/sucesso?loja=$_lojaIdA', 'approved');
      expect(_decide(legacy).kind, CatalogInitialRouteKind.appRoot,
          reason: 'sem a reescrita, o boot cairia no MyApp (AppStartRouter → /login)');
      final resolved =
          legacy.resolveUri(CatalogPaymentReturnLink.legacyReturnTarget(legacy)!);
      expect(resolved.origin, _origin);
      final d = _decide(resolved);
      expect(d.kind, CatalogInitialRouteKind.publicCatalogByLojaPath);
      expect(d.extractedSlugOrId, _lojaIdA);
      final r = CatalogPaymentReturnLink.parse(resolved)!;
      expect(r.clearsCart, isTrue);
    });

    test('tolera barra final', () {
      final t = CatalogPaymentReturnLink.legacyReturnTarget(
          Uri.parse('$_origin/pagamento/falha/?loja=$_lojaA'));
      expect(t.toString(), '/loja/loja-a?pagamento=falha');
    });

    test('retornos de plano, sem loja ou outras rotas ficam intocados', () {
      for (final u in [
        '$_origin/pagamento/sucesso?plano=pro',
        '$_origin/pagamento/sucesso?loja=$_lojaA&plano=pro',
        '$_origin/pagamento/sucesso',
        '$_origin/pagamento/sucesso?loja=',
        '$_origin/pagamento/sucesso?loja=minha-loja',
        '$_origin/pagamento/sucesso?loja=a%2Fb',
        '$_origin/sucesso?loja=$_lojaA',
        '$_origin/checkout/success?loja=$_lojaA',
        '$_origin/pedido/PedidoAaaaaaaaaaaaaa?loja=$_lojaA',
        '$_origin/planos/retorno?status=approved',
        '$_origin/mp-oauth-callback?code=x&state=y',
        '$_origin/mp-oauth-start',
        '$_origin/loja/$_lojaA?pagamento=sucesso',
      ]) {
        expect(CatalogPaymentReturnLink.legacyReturnTarget(Uri.parse(u)), isNull,
            reason: u);
      }
    });

    test('/pedido e retorno de plano continuam com o roteamento atual', () {
      final pedido = Uri.parse('$_origin/pedido/PedidoAaaaaaaaaaaaaa?loja=$_lojaA');
      expect(PublicOrderLink.isPublicOrderPath(pedido), isTrue);
      expect(PlanReturnLink.isPlanReturnPath(Uri.parse('$_origin/planos/retorno')),
          isTrue);
    });
  });

  group('cleanedRelativeUrl — URL limpa preservando a loja', () {
    test('remove marcador e query do MP, mantém filtros do catálogo', () {
      final u = _mpReturn('$_origin/loja/loja-a?cat=aneis&pagamento=sucesso', 'approved');
      expect(CatalogPaymentReturnLink.cleanedRelativeUrl(u), '/loja/loja-a?cat=aneis');
    });

    test('sem outros parâmetros fica só /loja/<loja>', () {
      final u = _mpReturn('$_origin/loja/loja-b?pagamento=falha', 'rejected');
      expect(CatalogPaymentReturnLink.cleanedRelativeUrl(u), '/loja/loja-b');
      expect(
          CatalogPaymentReturnLink.parse(Uri.parse(
              '$_origin${CatalogPaymentReturnLink.cleanedRelativeUrl(u)}')),
          isNull,
          reason: 'refresh depois da limpeza não repete aviso nem limpeza');
    });

    test('preserva vendedor (ref) e fragmento', () {
      final u = Uri.parse('$_origin/loja/loja-a?ref=vend1&pagamento=pendente&status=pending#x');
      expect(CatalogPaymentReturnLink.cleanedRelativeUrl(u), '/loja/loja-a?ref=vend1#x');
    });
  });

  group('consumeInitialUri / takePendingFor — boot web', () {
    setUp(CatalogPaymentReturnLink.debugResetPending);

    test('retorno novo: URL limpa e status entregue uma vez à mesma loja', () {
      final clean = CatalogPaymentReturnLink.consumeInitialUri(
          _mpReturn('$_origin/loja/loja-a?cat=aneis&pagamento=sucesso', 'approved'));
      expect(clean, '/loja/loja-a?cat=aneis');
      expect(CatalogPaymentReturnLink.takePendingFor(_lojaB), isNull,
          reason: 'loja B nunca recebe o retorno da loja A');
      final r = CatalogPaymentReturnLink.takePendingFor(_lojaA)!;
      expect(r.storeRef, _lojaA);
      expect(r.clearsCart, isTrue);
      expect(CatalogPaymentReturnLink.takePendingFor(_lojaA), isNull,
          reason: 'consumido uma vez por abertura');
    });

    test('retorno antigo /pagamento/*?loja= vira /loja/<loja> limpa', () {
      final clean = CatalogPaymentReturnLink.consumeInitialUri(
          _mpReturn('$_origin/pagamento/falha?loja=$_lojaIdA', 'rejected'));
      expect(clean, '/loja/$_lojaIdA');
      final resolved = Uri.parse(_origin).resolve(clean!);
      expect(_decide(resolved).kind, CatalogInitialRouteKind.publicCatalogByLojaPath);
      final r = CatalogPaymentReturnLink.takePendingFor(_lojaIdA)!;
      expect(r.status, CatalogPaymentReturnStatus.falha);
      expect(r.clearsCart, isFalse);
    });

    test('URLs sem retorno não mudam nada', () {
      for (final u in [
        '$_origin/loja/loja-a?cat=aneis',
        '$_origin/pagamento/sucesso?plano=pro',
        '$_origin/pedido/PedidoAaaaaaaaaaaaaa?loja=$_lojaA',
        '$_origin/mp-oauth-callback?code=x&state=y',
        '$_origin/',
      ]) {
        expect(CatalogPaymentReturnLink.consumeInitialUri(Uri.parse(u)), isNull, reason: u);
      }
      expect(CatalogPaymentReturnLink.takePendingFor(_lojaA), isNull);
    });
  });

  group('mensagens', () {
    test('sucesso é neutro (não afirma confirmação)', () {
      final m = CatalogPaymentReturnLink.message(CatalogPaymentReturnStatus.sucesso);
      expect(m, 'Pagamento recebido. Estamos confirmando seu pedido.');
      expect(m.toLowerCase(), isNot(contains('confirmado')));
    });

    test('pendente e falha', () {
      expect(CatalogPaymentReturnLink.message(CatalogPaymentReturnStatus.pendente),
          startsWith('Pagamento em processamento.'));
      expect(CatalogPaymentReturnLink.message(CatalogPaymentReturnStatus.falha),
          contains('carrinho'));
    });
  });
}
