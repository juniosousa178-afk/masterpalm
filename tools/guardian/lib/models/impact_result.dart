class ImpactResult {
  ImpactResult({
    required this.domains,
    this.services = const [],
    this.screens = const [],
    this.firestoreCollections = const [],
    this.hiveBoxes = const [],
    this.flows = const [],
    this.callers = const [],
    this.callees = const [],
    this.relatedRcas = const [],
    this.relatedRunbooks = const [],
  });

  final List<String> domains;
  final List<String> services;
  final List<String> screens;
  final List<String> firestoreCollections;
  final List<String> hiveBoxes;
  final List<String> flows;
  final List<String> callers;
  final List<String> callees;
  final List<String> relatedRcas;
  final List<String> relatedRunbooks;

  Map<String, dynamic> toJson() => {
        'domains': domains,
        'services': services,
        'screens': screens,
        'firestore_collections': firestoreCollections,
        'hive_boxes': hiveBoxes,
        'flows': flows,
        'callers': callers,
        'callees': callees,
        'related_rcas': relatedRcas,
        'related_runbooks': relatedRunbooks,
      };
}
