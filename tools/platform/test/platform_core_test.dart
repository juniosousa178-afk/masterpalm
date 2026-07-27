import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderRegistry', () {
    test('resolves registered instance', () {
      final registry = ProviderRegistry();
      final provider = _FakeAstProvider();
      registry.registerInstance<AstProvider>(provider);

      expect(registry.resolve<AstProvider>(), same(provider));
    });

    test('throws when provider is missing', () {
      final registry = ProviderRegistry();
      expect(
        () => registry.resolve<AstProvider>(),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('PlatformBootstrap', () {
    test('registers FileSystemAstProvider by default', () {
      final registry = ProviderRegistry();
      final config = PlatformConfig.forRepo('.');
      final core =
          PlatformBootstrap.forRepo('.', config: config, registry: registry);

      expect(core.ast(), isA<FileSystemAstProvider>());
    });
  });
}

class _FakeAstProvider implements AstProvider {
  @override
  String get reportPath => '/tmp/ast_report.json';

  @override
  Map<String, dynamic> loadReport() => {};

  @override
  void saveReport(Map<String, dynamic> report) {}

  @override
  int? complexityForMethod(String methodKey) => null;

  @override
  int? complexityForFile(String relPath) => null;

  @override
  int? linesForFile(String relPath) => null;

  @override
  List<String> callersForFile(String relPath) => [];

  @override
  bool hasImportCycle(List<String> changedFiles) => false;
}
