import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_initial_web_route.dart';
import 'package:master_palm/config/app_urls.dart';

/// Usa a mesma regra de host do app que [main] (evita regressão na raiz).
bool _isAppCatalogHost(String host) =>
    AppUrls.isDefaultMasterPalmCatalogHost(host);

void main() {
  group('CatalogRouteDecision (web) — checklist baseline APPSTARTFIX / anti-regressão', () {
    test('B1. app.mastepalm.com.br/ → appRoot', () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse('https://app.mastepalm.com.br/'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(d.kind, CatalogInitialRouteKind.appRoot);
    });

    test('B1b. app.mastepalm.com.br (host só, path implícito) → appRoot', () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse('https://app.mastepalm.com.br'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(d.kind, CatalogInitialRouteKind.appRoot);
    });

    test('B2. /loja/nathy-pratas-e-folheados → publicCatalogByLojaPath (vitrine por slug)', () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse(
            'https://app.mastepalm.com.br/loja/nathy-pratas-e-folheados'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(d.kind, CatalogInitialRouteKind.publicCatalogByLojaPath);
      expect(d.extractedSlugOrId, 'nathy-pratas-e-folheados');
    });

    test('B3. /loja → lojaPathOrSlugInvalid, não appRoot', () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse('https://app.mastepalm.com.br/loja'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(d.kind, CatalogInitialRouteKind.lojaPathOrSlugInvalid);
      expect(d.kind, isNot(CatalogInitialRouteKind.appRoot));
    });

    test('B4. ?loja=nathy-pratas-e-folheados → publicCatalogByLegacyQuery (legado)', () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse(
            'https://app.mastepalm.com.br/?loja=nathy-pratas-e-folheados'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(d.kind, CatalogInitialRouteKind.publicCatalogByLegacyQuery);
      expect(d.extractedSlugOrId, 'nathy-pratas-e-folheados');
    });

    test('B5. raiz app nunca → customDomainNotConfigured (evita ramo CatalogDomainBootstrapErrorApp na decisão estática)', () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse('https://app.mastepalm.com.br/'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(d.kind, CatalogInitialRouteKind.appRoot);
      expect(d.kind, isNot(CatalogInitialRouteKind.customDomainNotConfigured));
    });

    test('B6. minha-loja → inválido (nunca loja real)', () {
      final dPath = CatalogRouteDecision.fromUri(
        Uri.parse('https://app.mastepalm.com.br/loja/minha-loja'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(dPath.kind, CatalogInitialRouteKind.lojaPathOrSlugInvalid);
      final dQ = CatalogRouteDecision.fromUri(
        Uri.parse('https://app.mastepalm.com.br/?loja=minha-loja'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: null,
      );
      expect(dQ.kind, CatalogInitialRouteKind.legacyQueryInvalid);
    });

    test('B7. domínio próprio mapeado → customDomainPublicCatalog', () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse('https://catalogo.nathypratasefolheados.com.br/'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: true,
      );
      expect(d.kind, CatalogInitialRouteKind.customDomainPublicCatalog);
    });

    test('B8. domínio desconhecido → customDomainNotConfigured (loja não configurada)',
        () {
      final d = CatalogRouteDecision.fromUri(
        Uri.parse('https://loja-desconhecida-xyz99.example/'),
        isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
        isPublicMarketingHost: AppUrls.isPublicMarketingHost,
        customDomainMappingResolved: false,
      );
      expect(d.kind, CatalogInitialRouteKind.customDomainNotConfigured);
    });

    test('regressão: raiz do app nunca vira customDomainNotConfigured', () {
      for (final u in [
        Uri.parse('https://app.mastepalm.com.br/'),
        Uri.parse('https://app.mastepalm.com.br'),
        Uri.parse('https://app.masterpalm.com.br/'),
        Uri.parse('https://masterpalm-58c46.web.app/'),
      ]) {
        final d = CatalogRouteDecision.fromUri(
          u,
          isDefaultAppOrCatalogHostingHost: _isAppCatalogHost,
          isPublicMarketingHost: AppUrls.isPublicMarketingHost,
          customDomainMappingResolved: null,
        );
        expect(
          d.kind,
          isNot(CatalogInitialRouteKind.customDomainNotConfigured),
          reason: 'host=${u.host} path=${u.path} → ${d.kind}',
        );
        expect(
          d.kind,
          isNot(CatalogInitialRouteKind.customDomainAwaitingFirestore),
          reason: 'host default não deve aguardar Firestore de domínio: $u',
        );
      }
    });
  });
}
