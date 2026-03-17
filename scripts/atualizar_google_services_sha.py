#!/usr/bin/env python3
# scripts/atualizar_google_services_sha.py
# Adiciona o SHA-1 do Play App Signing ao Firebase e atualiza google-services.json.
# Requer: pip install google-auth requests
#
# Uso: python scripts/atualizar_google_services_sha.py

import json
import sys
from pathlib import Path
from urllib.parse import quote

# SHA-1 do certificado de assinatura do app (Google Play)
PLAY_APP_SIGNING_SHA1 = "11:E2:52:35:37:07:C6:C2:CB:D2:F2:DD:72:58:F2:6D:0E:8D:A4:FC"

PROJECT_ID = "masterpalm-58c46"
# APP_ID: mobilesdk_app_id do google-services.json (colons codificados na URL)
APP_ID = "1:950139833317:android:01d76e9d022ae1851ebd0c"
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
SERVICE_ACCOUNT_PATH = SCRIPT_DIR / "serviceAccountKey.json"
GOOGLE_SERVICES_PATH = PROJECT_ROOT / "android" / "app" / "google-services.json"


def get_access_token():
    """Obtém token OAuth2 usando service account."""
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import Request
    except ImportError:
        print("ERRO: Instale o pacote: pip install google-auth")
        sys.exit(1)

    credentials = service_account.Credentials.from_service_account_file(
        str(SERVICE_ACCOUNT_PATH),
        scopes=["https://www.googleapis.com/auth/firebase"],
    )
    credentials.refresh(Request())
    return credentials.token


def add_sha_to_firebase(token: str) -> bool:
    """Adiciona o SHA-1 ao app Android no Firebase via Management API."""
    try:
        import requests
    except ImportError:
        print("ERRO: Instale o pacote: pip install requests")
        sys.exit(1)

    # Colons no APP_ID precisam ser codificados na URL
    app_id_encoded = quote(APP_ID, safe="")
    parent = f"projects/-/androidApps/{app_id_encoded}"
    url = f"https://firebase.googleapis.com/v1beta1/{parent}/sha"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    body = {
        "shaHash": PLAY_APP_SIGNING_SHA1,
        "certType": "SHA_1",
    }

    print(f"Adicionando SHA-1 ao Firebase ({PROJECT_ID})...")
    r = requests.post(url, headers=headers, json=body, timeout=30)

    if r.status_code == 200:
        print("OK: SHA-1 adicionado com sucesso!")
        return True
    elif r.status_code == 409:
        print("OK: SHA-1 já estava registrado.")
        return True
    else:
        print(f"ERRO API ({r.status_code}): {r.text}")
        if r.status_code == 403:
            print("\nDica: A service account precisa da permissão 'Firebase Admin' ou 'Editor' no projeto.")
        return False


def update_google_services_json():
    """Atualiza google-services.json via Firebase CLI (se instalado)."""
    import subprocess

    firebase_cmd = "firebase"
    if sys.platform == "win32":
        firebase_cmd = "firebase.cmd"

    try:
        result = subprocess.run(
            [
                firebase_cmd,
                "apps:sdkconfig",
                "android",
                "--project", PROJECT_ID,
            ],
            capture_output=True,
            text=True,
            cwd=str(PROJECT_ROOT),
            timeout=15,
        )
        if result.returncode == 0 and result.stdout.strip():
            config = json.loads(result.stdout)
            # O output pode vir em formato diferente; ajustar conforme necessário
            if "project_info" in config or "client" in config:
                with open(GOOGLE_SERVICES_PATH, "w", encoding="utf-8") as f:
                    json.dump(config, f, indent=2, ensure_ascii=False)
                print(f"OK: google-services.json atualizado em {GOOGLE_SERVICES_PATH}")
                return True
    except FileNotFoundError:
        pass
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return False


def main():
    if not SERVICE_ACCOUNT_PATH.exists():
        print(f"ERRO: Arquivo não encontrado: {SERVICE_ACCOUNT_PATH}")
        sys.exit(1)

    token = get_access_token()
    if not add_sha_to_firebase(token):
        sys.exit(1)

    print("\nAtualizando google-services.json...")
    if update_google_services_json():
        print("\nConcluído! Recompile o app Android.")
        return

    print("\n" + "=" * 60)
    print("IMPORTANTE: Baixe o novo google-services.json manualmente:")
    print("1. Acesse: https://console.firebase.google.com/project/masterpalm-58c46/settings/general")
    print("2. Em 'Seus aplicativos', clique no app Android")
    print("3. Clique em 'Fazer download do google-services.json'")
    print("4. Substitua o arquivo em: android/app/google-services.json")
    print("=" * 60)


if __name__ == "__main__":
    main()
