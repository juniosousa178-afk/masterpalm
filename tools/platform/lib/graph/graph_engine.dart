import '../interfaces/ast_provider.dart';
import '../models/graph/graph_validation_result.dart';
import '../models/graph/project_graph.dart';
import 'ast_graph_mapper.dart';
import 'graph_builder.dart';
import 'graph_validator.dart';

/// Stateless coordinator that transforms AST data into [ProjectGraph].
class GraphEngine {
  GraphEngine({
    AstGraphMapper? mapper,
    GraphBuilder? builder,
    GraphValidator? validator,
  })  : _mapper = mapper ?? const AstGraphMapper(),
        _builder = builder ?? GraphBuilder(),
        _validator = validator ?? const GraphValidator();

  final AstGraphMapper _mapper;
  final GraphBuilder _builder;
  final GraphValidator _validator;

  ProjectGraph buildFromAstReport(Map<String, dynamic> report) {
    final data = _mapper.parse(report);
    final graph = _builder.build(data);
    final validation = _validator.validate(graph);
    if (!validation.valid) {
      throw StateError(
        'Invalid graph generated: ${validation.errors.join('; ')}',
      );
    }
    return graph;
  }

  ProjectGraph buildFromAstProvider(AstProvider astProvider) {
    return buildFromAstReport(astProvider.loadReport());
  }

  GraphValidationResult validate(ProjectGraph graph) =>
      _validator.validate(graph);
}
