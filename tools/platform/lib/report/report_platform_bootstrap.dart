import '../interfaces/ast_provider.dart';
import '../interfaces/graph_provider.dart';
import '../interfaces/report_provider.dart';
import '../core/provider_registry.dart';
import '../models/report/report_format.dart';
import '../providers/platform_report_provider.dart';
import 'report_engine.dart';
import 'renderers/html_report_renderer.dart';
import 'renderers/json_report_renderer.dart';
import 'renderers/markdown_report_renderer.dart';

/// Composition root for Report Engine integration.
class ReportPlatformBootstrap {
  const ReportPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    AstProvider? astProvider,
    GraphProvider? graphProvider,
    ReportEngine? reportEngine,
    ReportProvider? reportProvider,
  }) {
    if (registry.isRegistered<ReportProvider>()) return;

    final ast = astProvider ??
        (registry.isRegistered<AstProvider>()
            ? registry.resolve<AstProvider>()
            : null);
    final graph = graphProvider ??
        (registry.isRegistered<GraphProvider>()
            ? registry.resolve<GraphProvider>()
            : null);

    final engine = reportEngine ??
        ReportEngine(
          astProvider: ast,
          graphProvider: graph,
          renderers: {
            ReportFormat.markdown: const MarkdownReportRenderer(),
            ReportFormat.json: const JsonReportRenderer(),
            ReportFormat.html: const HtmlReportRenderer(),
          },
        );

    registry.registerInstance<ReportProvider>(
      reportProvider ?? PlatformReportProvider(engine: engine),
    );
  }
}
