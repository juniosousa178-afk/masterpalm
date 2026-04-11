/**
 * Carregado com node --import antes dos testes E2E.
 * Garante que o Admin SDK aponte para o Firestore Emulator.
 */
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
