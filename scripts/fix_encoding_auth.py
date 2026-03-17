# Fix only corrupted user-visible strings (encoding) in auth flow files.
# cadastro: n\xe3o -> não (Latin-1 byte in UTF-8 context)
# redefinir: same
import pathlib

base = pathlib.Path(__file__).resolve().parent.parent

for rel in ['lib/screens/auth/cadastro_screen_cliente.dart', 'lib/screens/auth/redefinir_senha_cliente_screen.dart']:
    path = base / rel
    raw = path.read_bytes()
    # Latin-1 byte 0xE3 (ã) used instead of UTF-8; replace only that sequence
    old_b = b"n\xe3o"
    new_b = "não".encode('utf-8')
    if old_b in raw:
        raw = raw.replace(old_b, new_b)
        path.write_bytes(raw)
        print(rel, "fixed")
    else:
        print(rel, "pattern not found")
