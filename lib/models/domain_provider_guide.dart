/// Conteúdo de tutorial DNS por provedor (somente UI — sem chamadas externas).
class DomainProviderGuide {
  const DomainProviderGuide({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.steps,
    required this.notes,
    this.propagationHint =
        'A propagação DNS costuma levar de alguns minutos até 48 horas, dependendo do provedor e do cache.',
  });

  final String id;
  final String title;
  final String shortDescription;
  final List<String> steps;
  final List<String> notes;
  final String propagationHint;
}
