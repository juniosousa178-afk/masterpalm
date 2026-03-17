# Funcionalidades quebradas ou com erros — MasterPalm

**Data:** 11/03/2025  
**Base:** Análise estática (`flutter analyze`), testes (`flutter test`), e inspeção do código.  
**Testes:** 46 passando. Linter: sem erros reportados no IDE.

---

## 1. Dependência descontinuada

| Item | Situação | Impacto |
|------|----------|---------|
| **firebase_dynamic_links** | Pacote **descontinuado** pelo Google (consta no `pubspec.yaml` linha 78). Não há uso no código (`lib/`). | Nenhum uso ativo; dependência morta. Pode ser removida do `pubspec.yaml`. Em versões futuras do SDK pode gerar avisos ou restrições. |

---

## 2. Web — upload de arquivos por path

| Funcionalidade | Situação | Motivo |
|----------------|----------|--------|
| **Upload de imagens por path no Web** | **Quebrado** quando usado no Web com arquivo local (path). | `UploadManager.enqueue(UploadRequest(platformFile: ...))` com `path` no Web lança `StateError('No web, use enqueueBytes() em vez de enqueue() com path.')` (ver `lib/services/upload_manager.dart`). |
| **Sincronização de catálogo (imagens locais) no Web** | **Quebrado** no Web se o produto tiver imagens com path local. | `CatalogoSyncService._uploadIfLocal()` usa `_uploader.enqueue(UploadRequest(platformFile: pf, ...))` com path. No Web não existe path; o fluxo não usa `enqueueBytes`. Chamado por `syncProduto`, `upsertFromProduto`, `syncAll` (estoque_screen, produto_form_screen, produto_combo_form_screen). |
| **ImageUploadService.uploadImage (path)** | **Incompatível com Web** (e risco de erro em tempo de execução). | Serviço usa `dart:io` e `ref.putFile(file)`. No Web, `dart:io` não está disponível (ou é stub). Usado por `ClientesFirestoreService` (avatar) e `ProdutosFirestoreService` (fallback quando `uploadImageFromBytes` não é usado). No Web, sync de cliente com avatar local ou de produto com imagem por path pode falhar. |
| **Cadastro de produto (imagens) no Web** | **Pode falhar** no Web em parte dos casos. | `CadastroProdutoScreen` usa `ref.putFile(File(path))` quando `f.bytes == null`. No Web o ideal é sempre enviar `withData: true` no file picker para ter bytes; se vier só path, o upload quebra. |

**Resumo:** No **Web**, qualquer fluxo que dependa de **path de arquivo local** para upload (logo da loja, banners, fotos de produto, avatar de cliente, publicação no catálogo) pode falhar, exceto onde já existir uso explícito de `enqueueBytes` / `putData` / `withData: true`.

---

## 3. Imagens locais no Web

| Funcionalidade | Situação | Motivo |
|----------------|----------|--------|
| **Exibição de imagem por path local no Web** | **Não funciona** por design. | `image_helper.dart`: em `kIsWeb`, paths locais não são suportados; `buildPlatformImage` retorna widget de erro e `buildPlatformImageProvider` retorna `null`. Comportamento documentado no código (“No Web, paths locais não funcionam”). |

Não é bug, mas qualquer tela que mostre foto salva só em path local (ex.: avatar do cliente antes de sync) no Web não exibirá a imagem.

---

## 4. Métodos deprecados (uso desencorajado)

| Onde | Situação | Motivo |
|------|----------|--------|
| **LimitsGuard** | Métodos marcados **@deprecated** | `canAddProduto(lojaId)` (e similares) sem `planId` estão deprecados; a documentação orienta usar overload com `planId` de `PlanosService`. Uso dos antigos ainda funciona, mas pode ficar desalinhado com limites por plano. |

---

## 5. Funcionalidades que podem falhar em cenários específicos

| Funcionalidade | Cenário | Risco |
|----------------|---------|--------|
| **Conversão de pré-pedido em venda** | Produto do pedido sem estoque ou com produto não encontrado (ex.: removido/alterado). | Código em `pre_pedidos_screen.dart` lança exceção e exibe “Falha ao registrar venda. Verifique se todos os produtos têm estoque disponível”. Comportamento esperado, mas a operação “converter em venda” falha nesses casos. |
| **Baixa de estoque (Firestore)** | Doc do produto não existir no Firestore no momento da baixa. | `estoque_transaction_service.dart` em alguns pontos faz `debugPrint` de “Update estoqueRef falhou (doc pode não existir)” e continua; a baixa no Hive pode ter sido feita, gerando inconsistência local/nuvem. |
| **Avatar do cliente na lista** | Mobile: path local; arquivo deletado ou inválido. | `clientes_screen.dart`: `hasAvatar = !kIsWeb && cliente.avatarPath != null && File(cliente.avatarPath!).existsSync()`. Se o arquivo não existir mais, o avatar não aparece (sem mensagem de erro). |
| **App Check (Web)** | Throttle / 400 / host não permitido. | No Web, em caso de falha na ativação do App Check, o app continua (não bloqueia login), mas fica sem proteção. Comportamento documentado no `main.dart`. |

---

## 6. O que foi verificado e está OK

- **flutter analyze:** executado (sem erros adicionais reportados no término da análise).
- **flutter test:** 46 testes passando.
- **Linter (IDE):** sem erros em `lib/`.
- **Backup:** export condicional (`backup_screen.dart` → web vs mobile) está correto.
- **Crashlytics:** desativado no Web no código, evitando MissingPluginException.
- **Uso de `File` / `dart:io` em telas:** onde usado (ex.: cliente avatar), está protegido com `!kIsWeb`.
- **Loja Config (logo/banners):** no Web usa `enqueueBytes` quando `kIsWeb`; no mobile usa `enqueue` com path — correto.

---

## Resumo prático

| Categoria | Situação |
|-----------|----------|
| **Dependência descontinuada** | 1 (firebase_dynamic_links; não usada). |
| **Quebrado no Web** | Upload por path (UploadManager, CatalogoSyncService, ImageUploadService.uploadImage, cadastro de produto sem bytes). |
| **Não funciona no Web por design** | Exibir imagem por path local (image_helper). |
| **Deprecados** | Métodos antigos de LimitsGuard (sem `planId`). |
| **Falhas em cenários específicos** | Conversão pré-pedido → venda (estoque/produto inexistente), baixa Firestore com doc inexistente, avatar com path inválido, App Check Web em falha. |

Recomendações prioritárias: (1) remover `firebase_dynamic_links` do `pubspec` se não houver plano de migração; (2) garantir que todos os fluxos de upload no Web usem apenas bytes (`enqueueBytes` / `putData` / `withData: true`) e nunca path; (3) em sync de cliente/produto no Web, usar apenas `uploadImageFromBytes` (ou equivalente) e não `uploadImage(path)`.
