// Contrato formal Rules V1 (design only) — NÃO altera firestore.rules.

enum PdvV1MarkerKind { legado, v1 }

enum PdvV1RulesSecurityLevel {
  l1LegacyPermissive,
  l2V1Hardening,
  l3StrongNotAchievableWithCurrentEstoqueRules,
}

class PdvV1MarkerV1CreateSpec {
  const PdvV1MarkerV1CreateSpec({
    required this.field,
    required this.required,
    required this.fixedValue,
    required this.immutableAfterCreate,
  });

  final String field;
  final bool required;
  final String? fixedValue;
  final bool immutableAfterCreate;
}

const pdvV1MarkerV1CreateFields = <PdvV1MarkerV1CreateSpec>[
  PdvV1MarkerV1CreateSpec(
    field: 'protocolVersion',
    required: true,
    fixedValue: '1',
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'origem',
    required: true,
    fixedValue: 'pdv',
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'lojaId',
    required: true,
    fixedValue: null,
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'operationId',
    required: true,
    fixedValue: null,
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'saleId',
    required: true,
    fixedValue: null,
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'baixaAplicada',
    required: true,
    fixedValue: 'true',
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'estornoAplicado',
    required: true,
    fixedValue: 'false',
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'txItemsHash',
    required: true,
    fixedValue: null,
    immutableAfterCreate: true,
  ),
  PdvV1MarkerV1CreateSpec(
    field: 'appliedAt',
    required: true,
    fixedValue: null,
    immutableAfterCreate: true,
  ),
];

class PdvV1MarkerRemoteTransition {
  const PdvV1MarkerRemoteTransition({
    required this.from,
    required this.to,
    required this.allowed,
    required this.allowedFields,
    required this.forbiddenFields,
    required this.justification,
  });

  final String from;
  final String to;
  final bool allowed;
  final List<String> allowedFields;
  final List<String> forbiddenFields;
  final String justification;
}

const pdvV1MarkerRemoteTransitions = <PdvV1MarkerRemoteTransition>[
  PdvV1MarkerRemoteTransition(
    from: '(create V1)',
    to: 'baixa_aplicada',
    allowed: true,
    allowedFields: [
      'protocolVersion',
      'origem',
      'lojaId',
      'operationId',
      'saleId',
      'baixaAplicada=true',
      'estornoAplicado=false',
      'txItemsHash',
      'appliedAt',
      'quantidadeDocumentosAfetados',
    ],
    forbiddenFields: ['baixaAplicada=false', 'partial_effects'],
    justification: 'Create-atômico único; sem false→true',
  ),
  PdvV1MarkerRemoteTransition(
    from: 'baixa_aplicada',
    to: 'effects_metadata',
    allowed: true,
    allowedFields: [
      'updatedAt',
      'syncTimestamps',
      'operationCompletionMetadata'
    ],
    forbiddenFields: ['txItemsHash', 'saleId', 'baixaAplicada'],
    justification: 'Metadados pós-baixa não alteram idempotência',
  ),
  PdvV1MarkerRemoteTransition(
    from: 'baixa_aplicada',
    to: 'estorno_aplicado',
    allowed: false,
    allowedFields: [],
    forbiddenFields: ['estornoAplicado=true sem protocolo estorno'],
    justification: 'Estorno fora V1 inicial — protocolo separado futuro',
  ),
  PdvV1MarkerRemoteTransition(
    from: 'legado',
    to: 'v1_upgrade',
    allowed: false,
    allowedFields: [],
    forbiddenFields: ['protocolVersion=1 em update legado'],
    justification: 'Legado não migra via update cliente',
  ),
];

PdvV1MarkerKind pdvV1ClassifyMarker({
  required int protocolVersion,
  required String origem,
}) {
  if (protocolVersion == 1 && origem == 'pdv') {
    return PdvV1MarkerKind.v1;
  }
  return PdvV1MarkerKind.legado;
}

const pdvV1RulesV1Limits = <String>[
  'Rules V1 não provam genericamente alteração de N docs estoque no mesmo commit.',
  'Rules V1 não eliminam fraude enquanto estoque_produtos permitir write amplo.',
  'Rules V1 = hardening L2, não L3 contra cliente comprometido.',
  'Marcador V1 isolado nunca basta para recovery sem journal local.',
  'TX atômica garante crash para cliente honesto; divergência → manual.',
];

const pdvV1RulesTargetLevel = PdvV1RulesSecurityLevel.l2V1Hardening;
