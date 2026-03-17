# Análise do APK MasterPalm – Erros, Pontos Negativos e Riscos Futuros

**Data:** Fevereiro 2026  
**Escopo:** Código Dart/Flutter, Firestore, Android build, dependências e segurança.

---

## 1. Resumo executivo

O projeto está **funcional e bem estruturado**: Firestore com regras restritivas, sem regras `allow read, write: if true`, autenticação e limites por plano. Existem, porém, **pontos de atenção** (segurança, manutenção, desempenho) e **riscos futuros** que valem correção ou monitoramento.

---

## 2. Erros e problemas atuais

### 2.1 Análise estática (Dart)

- **`dart analyze`**: Pode demorar em projetos grandes; não foram encontrados erros de compilação óbvios nos arquivos revisados.
- **Recomendação**: Rodar `dart analyze` e `flutter analyze` antes de cada release e corrigir todos os `info`/`warning` que fizerem sentido.

### 2.2 Tratamento de dados corrompidos em `getClienteLogado` (cliente_auth_service.dart)

- O método `getClienteLogado()` usa `json.decode(dadosJson)` dentro de try/catch; em caso de JSON corrompido em SharedPreferences o catch retorna `null`, o que é aceitável.
- **Risco menor**: Se no futuro o formato salvo mudar, pode haver incompatibilidade.
- **Ação**: Opcional – validar estrutura do map retornado (ex.: chaves esperadas) antes de usar; em migrações, tratar versões antigas do formato.

### 2.3 Uso de `// ignore` e `ignore_for_file`

- Vários arquivos usam `// ignore:` ou `ignore_for_file` (ex.: roleta_web_widget_v3, pre_pedidos_screen, config_pagamentos_screen, firebase_options).
- **Risco**: Esconder avisos reais (ex.: tipo, lint).
- **Recomendação**: Reduzir ao mínimo; onde for necessário, documentar o motivo em comentário.

---

## 3. Pontos negativos e dívida técnica

### 3.1 Arquivos muito grandes

- **public_catalog_screen.dart**: ~4.541 linhas.
- **home_screen.dart**: ~2.357 linhas.
- **loja_config_screen.dart**: ordem de milhares de linhas.
- **config_pagamentos_simples_screen.dart**: muito grande.

**Impacto**: Dificulta revisão, testes e refatoração; aumenta risco de conflitos no Git.  
**Recomendação**: Quebrar em widgets/screens menores, extrair lógica para serviços ou presenters.

### 3.2 Muitos `debugPrint` / `print`

- Centenas de usos em `lib/` (ex.: main, public_catalog_screen, carrinho_sheet_web, full_sync_service, frete_service, etc.).
- **Risco**: Logs em produção podem expor dados ou poluir o console; em release o Tree Shaking pode remover parte, mas não é garantido para todos os casos.
- **Recomendação**: Usar um logger com níveis (ex.: `logger` ou `logging`) e desligar debug em release; evitar logar dados sensíveis.

### 3.4 Casts diretos (`as int`, `as String`, `as Map`)

- Muitos casts em serviços (pre_pedido_service, catalogo_venda_service, marketplaces, etc.) ao ler Firestore/JSON.
- **Risco**: Se o tipo vier errado, gera exceção em runtime.
- **Recomendação**: Usar os utilitários existentes (`safe_parse`, `safe_cast`) ou padrão defensivo (ex.: `as int? ?? 0`) onde fizer sentido.

### 3.5 TODOs / FIXMEs no código

- Vários arquivos com TODO/FIXME (full_sync_service, store_resolver_unified, limits_guard, migrate_collections_service, etc.).
- **Recomendação**: Listar em um backlog e ir resolvendo ou documentando decisão de “não fazer”.

---

## 4. Riscos de segurança

### 4.1 Senha do cliente do catálogo (SHA256 sem salt)

- **ClienteAuthService**: Senha hasheada com SHA256 e armazenada no Firestore (`senhaHash`).
- **Risco**: SHA256 sem salt é vulnerável a rainbow tables e ataques por dicionário em caso de vazamento do banco.
- **Recomendação**: Migrar para um esquema com salt (ex.: bcrypt, scrypt ou Firebase Auth) e, se possível, não armazenar hash de senha no Firestore para clientes do catálogo.

### 4.2 Senha do keystore no código (Android)

- **android/app/build.gradle.kts**: Se usar o keystore embutido (`release.keystore`), a senha `masterpalm2024` está no código.
- **Risco**: Qualquer pessoa com acesso ao repositório (ou build) pode usar a chave se tiver o arquivo `.keystore`.
- **Recomendação**: Usar sempre `key.properties` (já no .gitignore) em CI e para desenvolvedores; não commitar keystore nem senhas. Remover senha fixa do script quando o keystore for 100% externo.

### 4.3 Tokens e credenciais

- Tokens (MP, PagSeguro, Ton, InfinitePay, Melhor Envio, Frenet, SuperFrete, TikTok, ML, etc.) vêm de config (Firestore/UI), não hardcoded – **bom**.
- API Key da Globo da Sorte vem do Remote Config – **bom**.
- **Recomendação**: Manter esse padrão; não colocar nunca chaves/tokens em código ou em repositório.

### 4.4 Firestore Rules

- Não há regras do tipo `allow read, write: if true`.
- Uso de `isAdminOrSystem()`, `belongsToStore(lojaId)`, validações de tamanho e estrutura em writes públicos – **positivo**.
- **Recomendação**: Revisar periodicamente novas coleções e garantir que nenhuma fique aberta por engano.

---

## 5. Riscos futuros (performance, custo, escala)

### 5.1 Firestore – leituras e custo

- Listeners e queries em várias telas (vendas, estoque, clientes, catálogo, etc.); syncs que podem trazer muitos documentos.
- **Risco**: Aumento de custo e latência com muitas lojas/usuários e documentos grandes.
- **Recomendação**: Paginar listas, usar cache (já há uso de cache em partes do catálogo), limitar listeners às telas abertas e evitar leituras desnecessárias (ex.: campos grandes quando não precisar).

### 5.2 Listeners em tempo real (FirestoreCriticalListenerService)

- Documentação (PLANO_MELHORIAS) cita risco para lojas com muitos produtos (ex.: >500).
- **Recomendação**: Garantir que listeners sejam cancelados no `dispose`; avaliar limite ou paginação se uma loja crescer muito.

### 5.3 Dependências

- **pubspec.yaml**: Muitas dependências (Firebase, pagamentos, fretes, marketplaces, etc.).
- **Risco**: Atualizações quebradas, vulnerabilidades, aumento do tamanho do APK.
- **Recomendação**: Atualizar com cuidado (ler changelogs); rodar `dart pub outdated` e planejar upgrades; revisar dependências que não forem mais usadas.

### 5.4 Android: minSdk e targetSdk

- **targetSdk = 34**, **compileSdk = 36**; minSdk vem do Flutter.
- **Recomendação**: Acompanhar requisitos da Play Store (targetSdk mínimo) e testar em dispositivos com minSdk do projeto.

---

## 6. Outros pontos

### 6.1 Firebase / firebase_options.dart

- `firebase_options.dart` é gerado (FlutterFire CLI) e contém IDs de projeto; normalmente não é sensível, mas o arquivo fica no repo.
- **Recomendação**: Manter como está; não adicionar chaves secretas ali.

### 6.2 ProGuard e ofuscação

- Release com `isMinifyEnabled = true`, `isShrinkResources = true` e ProGuard – **bom** para tamanho e ofuscação básica.
- **Recomendação**: Manter regras ProGuard para Firebase/plugins atualizadas ao atualizar SDKs.

### 6.3 Sessão do cliente (SharedPreferences)

- Dados de sessão do cliente (id, nome, email, telefone, lojaId) em SharedPreferences.
- **Risco**: Em dispositivo rootado ou com backup desprotegido, podem ser lidos.
- **Recomendação**: Aceitável para dados não críticos; não armazenar senha ou token sensível em pref. Se no futuro houver dados mais sensíveis, considerar criptografia (ex.: flutter_secure_storage).

---

## 7. Checklist de ações sugeridas

| Prioridade | Ação |
|-----------|------|
| Média | (Opcional) Validar estrutura do JSON em `getClienteLogado()` e tratar formato antigo em migrações. |
| Alta | Remover ou externalizar senha do keystore do `build.gradle.kts`; usar só `key.properties`. |
| Média | Planejar refatoração de telas gigantes (public_catalog_screen, home_screen, loja_config_screen). |
| Média | Reduzir `debugPrint`/`print` e adotar logger com nível (desligar debug em release). |
| Média | Revisar TODOs/FIXMEs e fechar ou documentar. |
| Baixa | Melhorar hashing de senha do cliente do catálogo (salt ou migrar para Auth). |
| Baixa | Padronizar leituras de Firestore com safe_parse/safe_cast onde ainda houver cast direto. |
| Contínuo | Rodar `dart analyze` / `flutter analyze` antes de cada release. |
| Contínuo | Revisar regras do Firestore ao adicionar coleções ou novos fluxos. |

---

## 8. Conclusão

O APK está **em condição utilizável e com boas bases** (regras Firestore, limites por plano, múltiplos gateways de pagamento, ProGuard). Os principais **erros/riscos** são: possível falha de `try/catch` em `getClienteLogado`, senha do keystore no código e hashing fraco da senha do cliente. Os **pontos negativos** principais são **arquivos muito grandes** e **excesso de logs**. Os **riscos futuros** concentram-se em **custo e desempenho do Firestore**, **atualização de dependências** e **escala de listeners**. Tratar os itens de prioridade alta e média reduz bastante risco e facilita manutenção futura.
