// Catálogo de efeitos pós-baixa — classificação Fase 6.3 (design only).

import 'pdv_v1_contract.dart';

class PdvV1EffectSpec {
  const PdvV1EffectSpec({
    required this.nome,
    required this.fonteVerdade,
    required this.classe,
    required this.derivavel,
    required this.idempotenteHoje,
    required this.chaveIdempotencia,
    required this.subestadoObrigatorio,
    required this.recoveryPossivel,
    required this.consequenciaFalha,
  });

  final String nome;
  final String fonteVerdade;
  final PdvV1EffectClass classe;
  final bool derivavel;
  final bool idempotenteHoje;
  final String chaveIdempotencia;
  final PdvV1EffectSubstate? subestadoObrigatorio;
  final String recoveryPossivel;
  final String consequenciaFalha;
}

/// Espelha auditoria de vendas_service.dart pós baixarEstoqueTransactionBatch.
const pdvV1EffectsCatalog = <PdvV1EffectSpec>[
  PdvV1EffectSpec(
    nome: 'Baixa estoque + marcador V1',
    fonteVerdade: 'Firestore TX (estoque_produtos + estoque_baixa_pagamento)',
    classe: PdvV1EffectClass.criticalInTransaction,
    derivavel: false,
    idempotenteHoje: false,
    chaveIdempotencia: 'operationId + txItemsHash',
    subestadoObrigatorio: null,
    recoveryPossivel: 'GET marcador + retry TX idempotente',
    consequenciaFalha: 'Estoque órfão ou dupla baixa',
  ),
  PdvV1EffectSpec(
    nome: 'Hive venda',
    fonteVerdade: 'Journal preparedSnapshot + saleId',
    classe: PdvV1EffectClass.postProcessIdempotent,
    derivavel: true,
    idempotenteHoje: false,
    chaveIdempotencia: 'saleId + snapshotHash',
    subestadoObrigatorio: PdvV1EffectSubstate.hiveSaleCompleted,
    recoveryPossivel: 'HiveUpsertPorSaleId a partir do journal',
    consequenciaFalha: 'Venda ausente localmente',
  ),
  PdvV1EffectSpec(
    nome: 'Hive produtos / refresh estoque',
    fonteVerdade: 'txItems + resultado TX remoto',
    classe: PdvV1EffectClass.derivedRecomputable,
    derivavel: true,
    idempotenteHoje: false,
    chaveIdempotencia: 'operationId + productId + celula',
    subestadoObrigatorio: PdvV1EffectSubstate.productCacheRefreshCompleted,
    recoveryPossivel: 'atualizarHiveAposTransacao ou re-fetch remoto',
    consequenciaFalha: 'Estoque local divergente',
  ),
  PdvV1EffectSpec(
    nome: 'Combo cap (ComboKitStockService)',
    fonteVerdade: 'TX secundária + txItems originais congelados',
    classe: PdvV1EffectClass.postProcessIdempotent,
    derivavel: false,
    idempotenteHoje: false,
    chaveIdempotencia: 'operationId:combo_cap',
    subestadoObrigatorio: PdvV1EffectSubstate.comboCapCompleted,
    recoveryPossivel: 'Retry TX combo com mesmo operationId sub-op',
    consequenciaFalha: 'Disponibilidade combo incorreta',
  ),
  PdvV1EffectSpec(
    nome: 'Catálogo web (CatalogoWebAposEstoqueService)',
    fonteVerdade: 'Resultados TX + produtosBox',
    classe: PdvV1EffectClass.postProcessIdempotent,
    derivavel: true,
    idempotenteHoje: false,
    chaveIdempotencia: 'operationId:catalog',
    subestadoObrigatorio: PdvV1EffectSubstate.catalogProjectionCompleted,
    recoveryPossivel: 'Re-sync catálogo a partir de estoque remoto',
    consequenciaFalha: 'Catálogo web desatualizado',
  ),
  PdvV1EffectSpec(
    nome: 'Remoção catálogo estoque zero',
    fonteVerdade: 'quantidadeTotalAtualizada == 0 pós TX',
    classe: PdvV1EffectClass.derivedRecomputable,
    derivavel: true,
    idempotenteHoje: false,
    chaveIdempotencia: 'productId + zero_flag',
    subestadoObrigatorio: PdvV1EffectSubstate.catalogProjectionCompleted,
    recoveryPossivel: 'Recomputar a partir de estoque remoto',
    consequenciaFalha: 'Produto visível com estoque zero',
  ),
  PdvV1EffectSpec(
    nome: 'Movimentação estoque',
    fonteVerdade: 'txResults + saleId',
    classe: PdvV1EffectClass.postProcessIdempotent,
    derivavel: true,
    idempotenteHoje: false,
    chaveIdempotencia: 'saleId:produtoId:qty',
    subestadoObrigatorio: PdvV1EffectSubstate.movementCompleted,
    recoveryPossivel: 'Registrar saída idempotente',
    consequenciaFalha: 'Histórico incompleto (não bloqueia venda)',
  ),
  PdvV1EffectSpec(
    nome: 'SyncQueue venda',
    fonteVerdade: 'Hive vendaHiveKey confirmado',
    classe: PdvV1EffectClass.postProcessIdempotent,
    derivavel: false,
    idempotenteHoje: true,
    chaveIdempotencia: 'upsertVenda_{lojaId}_{entityKey}',
    subestadoObrigatorio: PdvV1EffectSubstate.syncQueueCompleted,
    recoveryPossivel: 'Enfileirar após Hive upsert',
    consequenciaFalha: 'Sync atrasado',
  ),
  PdvV1EffectSpec(
    nome: 'Sync remoto venda',
    fonteVerdade: 'estoque_vendas/{saleId}',
    classe: PdvV1EffectClass.postProcessIdempotent,
    derivavel: false,
    idempotenteHoje: true,
    chaveIdempotencia: 'saleId (doc id Firestore)',
    subestadoObrigatorio: PdvV1EffectSubstate.syncRemoteCompleted,
    recoveryPossivel: 'syncVenda idempotente',
    consequenciaFalha: 'Venda só local',
  ),
  PdvV1EffectSpec(
    nome: 'Conta receber / fiado',
    fonteVerdade: 'Journal fiado + saleId',
    classe: PdvV1EffectClass.postProcessIdempotent,
    derivavel: false,
    idempotenteHoje: false,
    chaveIdempotencia: 'saleId:conta_receber',
    subestadoObrigatorio: PdvV1EffectSubstate.receivableCompleted,
    recoveryPossivel: 'Criar CR uma vez após Hive upsert',
    consequenciaFalha: 'Fiado sem CR',
  ),
];
