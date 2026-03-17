# One-off: fix only corrupted UI string literals in verify_email_screen.dart
# Byte 0x98 was used instead of proper UTF-8. Replace exact sequences only.
import pathlib

path = pathlib.Path(__file__).resolve().parent.parent / 'lib' / 'screens' / 'verify_email_screen.dart'
raw = path.read_bytes()

replacements = [
    (b"Sess\x98o expirada. Fa\x98a login novamente.", "Sessão expirada. Faça login novamente."),
    (b"E-mail ainda n\x98o verificado. Clique no link enviado.", "E-mail ainda não verificado. Clique no link enviado."),
    (b"Erro ao verificar. Verifique sua conex?o e tente novamente.", "Erro ao verificar. Verifique sua conexão e tente novamente."),
    (b"Quase l\x98!", "Quase lá!"),
    (b"Enviamos um e-mail de confirma\x98\x98o para", "Enviamos um e-mail de confirmação para"),
    (b"N\x98o esque\x98a de verificar a pasta de spam.", "Não esqueça de verificar a pasta de spam."),
    (b"J\x98 verifiquei", "Já verifiquei"),
    (b"// Tela de verifica??o de e-mail", "// Tela de verificação de e-mail"),
]

for old_b, new_str in replacements:
    new_b = new_str.encode('utf-8')
    if old_b in raw:
        raw = raw.replace(old_b, new_b)

path.write_bytes(raw)
print("Done. Replaced patterns.")
