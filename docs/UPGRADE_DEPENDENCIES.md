# Atualização de dependências (Flutter e Firebase)

Passos para atualizar Flutter SDK e pacotes principais **sem quebrar** o app. Fazer em branch e testar antes de merge.

---

## Antes de atualizar

1. `git checkout -b upgrade-deps-YYYY-MM`
2. `flutter doctor`
3. Rodar testes: `flutter test test/vendas_service_test.dart test/store_access_guard_test.dart`
4. Anotar versões atuais: `flutter --version` e versões no `pubspec.yaml` (firebase_core, cloud_firestore, hive, etc.)

---

## Ordem sugerida

### 1. Flutter SDK

```bash
flutter upgrade
```

- Depois: `flutter pub get`, `flutter analyze`, rodar app (login, sync, uma tela de vendas/catálogo).
- Se der breaking change, ver [flutter.dev/docs/release/breaking-changes](https://docs.flutter.dev/release/breaking-changes).

### 2. Pacotes Firebase

- Atualizar em conjunto (firebase_core, firebase_auth, cloud_firestore, firebase_storage, etc.) dentro do mesmo major quando possível.
- Ver [pub.dev](https://pub.dev) e changelog de cada pacote.
- Testar: login, Firestore read/write, Storage upload, App Check (token debug em dev).

### 3. Hive

- Changelog em [pub.dev/packages/hive](https://pub.dev/packages/hive). Cuidado com mudanças em TypeAdapter ou nomes de boxes.
- Rodar app e abrir telas que usam Hive (home, vendas, sync).

### 4. Outros pacotes

- `flutter pub outdated` para ver o que está atrasado.
- Atualizar de um em um (ou em grupos pequenos) e rodar testes + smoke manual.

---

## Depois de atualizar

1. `flutter clean && flutter pub get`
2. `flutter analyze`
3. Testes automatizados (se houver).
4. Checklist de release (`docs/CHECKLIST_RELEASE.md`): login, sync, catálogo, uma venda.
5. Commit com mensagem clara: “chore: upgrade Flutter X.Y / firebase_core X.Y / …”.

---

## Revisão periódica

- A cada 6 meses (ou antes de release grande): rodar `flutter pub outdated`, ler resumo de breaking changes do Flutter e do Firebase (blog/changelog), e atualizar este doc se o processo mudar.

---

## Pacotes críticos (não atualizar sem testar)

| Pacote | Uso |
|--------|-----|
| firebase_core | Inicialização Firebase |
| cloud_firestore | Dados remotos |
| firebase_auth | Login |
| firebase_storage | Upload de imagens |
| hive | Dados locais, sync queue |
| connectivity_plus | Listener de rede (SyncQueue) |
