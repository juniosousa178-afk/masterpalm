# 🎯 Plano de Correções Completas - MasterPalm

## 📋 Visão Geral do Sistema

**MasterPalm** é um e-commerce completo com:
- Multi-tenancy: cada usuário tem sua loja independente (isolamento por `lojaId`)
- Controle total: vendas, estoque, clientes, fornecedores, precificação, catálogo
- Hierarquia: Admin pode cadastrar vendedores vinculados
- Sincronização: Hive (local) ↔ Firestore (cloud) para troca de dispositivo
- Catálogo web público: acessível via URL única por loja

## 🔴 Problemas Atuais Identificados

### 1. **Config não sincroniza com Firestore**
- ❌ Logos e banners não aparecem no catálogo
- ❌ Estrutura `media.desktop`/`media.mobile` não está sendo salva corretamente
- ❌ Erro de type cast ao ler do Firestore

### 2. **Roleta da Sorte - Lógica Incorreta**
- ❌ Cupom pode ser usado imediatamente (deveria ser só na próxima compra)
- ❌ Cupom não tem validade (deveria expirar em 60 dias)
- ❌ Cupom não expira após uso
- ❌ Roleta não está no catálogo web

### 3. **Modo Campanha**
- ❌ Não está no catálogo web
- ⚠️ Gera número mesmo sem campanha ativa

### 4. **Sincronização Incompleta**
- ⚠️ Nem todas as telas sincronizam com Firestore
- ⚠️ Risco de perda de dados ao trocar de celular

### 5. **Isolamento por lojaId**
- ⚠️ Verificar se todas as queries filtram por lojaId
- ⚠️ Vendedores vinculados devem usar banco do admin

---

## ✅ Correções Planejadas

### FASE 1: Correção Imediata da Config (URGENTE)

#### 1.1 Corrigir salvamento de logos/banners
- [x] Implementar estrutura `media.desktop`/`media.mobile`
- [x] Corrigir type cast ao ler do Firestore
- [ ] Testar salvamento e leitura
- [ ] Verificar aparição no preview e catálogo web

#### 1.2 Adicionar logs detalhados
- [x] Logs de salvamento (💾)
- [ ] Logs de leitura
- [ ] Verificar no Firestore Console

---

### FASE 2: Modelo de Cupom da Roleta

#### 2.1 Criar novo modelo `CupomRoleta`
```dart
class CupomRoleta {
  String id;              // UUID único
  String lojaId;          // Loja que gerou
  String clienteId;       // Cliente que ganhou (pode ser vazio se anônimo)
  String clienteEmail;    // Email/telefone para identificar

  int desconto;           // Percentual de desconto (ex: 10 = 10%)
  DateTime dataGanho;     // Quando ganhou
  DateTime dataExpiracao; // dataGanho + 60 dias

  bool utilizado;         // Se já foi usado
  DateTime? dataUso;      // Quando foi usado
  String? vendaId;        // ID da venda onde foi usado

  bool expirado;          // Se passou dos 60 dias
}
```

#### 2.2 Lógica da Roleta
- [ ] Ao girar: gera cupom com `utilizado = false`
- [ ] Salva no Hive: `cupons_roleta_{lojaId}`
- [ ] Salva no Firestore: `lojas/{lojaId}/cupons_roleta/{cupomId}`
- [ ] Cliente recebe código do cupom (ex: `SORTE2024-ABC123`)
- [ ] Cupom só pode ser usado em compra FUTURA (não na atual)
- [ ] Ao usar: marca `utilizado = true` e `dataUso = now()`
- [ ] Sistema verifica expiração: `now() > dataExpiracao`

#### 2.3 Adicionar roleta no public_catalog_screen
- [ ] Botão "Roleta da Sorte" no catálogo
- [ ] Modal com a roleta
- [ ] Form para email/telefone do cliente
- [ ] Após girar: mostra cupom gerado
- [ ] Cliente anota o código

---

### FASE 3: Modo Campanha no Catálogo

#### 3.1 Verificar modelo `CampanhaSorteio`
- [ ] Deve ter `ativo: bool`
- [ ] Deve ter `dataInicio` e `dataFim`
- [ ] Isolado por `lojaId`

#### 3.2 Adicionar no public_catalog_screen
- [ ] Verificar se há campanha ativa
- [ ] Se sim: gerar número de sorteio ao finalizar compra
- [ ] Mostrar número para o cliente
- [ ] Salvar no Firestore: `lojas/{lojaId}/numeros_sorteio/{numero}`

---

### FASE 4: Sincronização Completa Hive ↔ Firestore

#### 4.1 Identificar todas as entidades
- [ ] Produtos
- [ ] Vendas
- [ ] Clientes
- [ ] Fornecedores
- [ ] Categorias
- [ ] Estoque
- [ ] Fechamentos
- [ ] Config da loja
- [ ] Cupons
- [ ] Campanhas
- [ ] Números de sorteio

#### 4.2 Garantir sincronização bidirecional
Para cada entidade:
- [ ] Ao criar/editar: salva Hive + Firestore
- [ ] Ao logar: carrega do Firestore → Hive
- [ ] Ao deslogar: limpa Hive local
- [ ] Conflitos: Firestore prevalece (source of truth)

#### 4.3 Implementar serviço de sync
```dart
class FullSyncService {
  // Faz sync completo ao logar
  static Future<void> syncAll(String lojaId) async {
    await syncProdutos(lojaId);
    await syncVendas(lojaId);
    await syncClientes(lojaId);
    // ... etc
  }

  // Sync incremental em background
  static Future<void> syncInBackground(String lojaId) async {
    // Verifica mudanças recentes
    // Sincroniza apenas o que mudou
  }
}
```

---

### FASE 5: Isolamento e Multi-tenancy

#### 5.1 Verificar todas as queries Firestore
- [ ] TODAS devem filtrar por `lojaId`
- [ ] Vendedores: queries filtram por `lojaAdminId` do vendedor

#### 5.2 Estrutura Firestore
```
lojas/
  {lojaId}/
    config/
      config       # Publicado
    draft_config/
      config       # Rascunho
    produtos/
      {produtoId}  # Publicados
    draft_produtos/
      {produtoId}  # Rascunho
    vendas/
      {vendaId}
    clientes/
      {clienteId}
    fornecedores/
      {fornecedorId}
    cupons_roleta/
      {cupomId}
    campanhas/
      {campanhaId}
    numeros_sorteio/
      {numero}
```

#### 5.3 Hierarquia Admin → Vendedor
- [ ] Vendedor tem campo `adminLojaId`
- [ ] Vendedor opera no banco do admin
- [ ] Vendedor não vê dados de outros vendedores
- [ ] Admin vê tudo

---

## 🚀 Ordem de Implementação

1. **AGORA**: Corrigir config (logos/banners) - BLOQUEADOR
2. **Hoje**: Modelo cupom roleta + lógica
3. **Hoje**: Adicionar roleta no catálogo web
4. **Amanhã**: Modo campanha no catálogo
5. **Próximos dias**: Sincronização completa
6. **Final**: Testes de isolamento e multi-tenancy

---

## 📊 Checklist de Teste Final

### Config
- [ ] Logos aparecem no preview
- [ ] Logos aparecem no catálogo web
- [ ] Banners aparecem no preview
- [ ] Banners aparecem no catálogo web
- [ ] Cores aplicadas corretamente
- [ ] Troca de celular: config persiste

### Roleta
- [ ] Gira e sorteia desconto
- [ ] Gera cupom com código único
- [ ] Cupom NÃO pode ser usado na compra atual
- [ ] Cupom pode ser usado em compra futura
- [ ] Cupom expira em 60 dias
- [ ] Cupom expira após 1 uso
- [ ] Roleta aparece no catálogo web
- [ ] Cliente consegue girar e receber cupom

### Campanha
- [ ] Só gera número se campanha ativa
- [ ] Número mostrado ao cliente
- [ ] Número salvo no Firestore
- [ ] Campanha aparece no catálogo web

### Sincronização
- [ ] Login: dados baixados do Firestore
- [ ] Mudança: salva Hive + Firestore
- [ ] Troca celular: todos dados restaurados
- [ ] Logout: Hive limpo

### Isolamento
- [ ] Loja A não vê dados da Loja B
- [ ] Vendedor vê apenas dados do admin dele
- [ ] Queries sempre filtram por lojaId

---

**Status**: 🔴 Em andamento
**Última atualização**: 2025-12-21
