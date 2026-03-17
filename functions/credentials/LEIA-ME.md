# Credenciais OAuth / Sensíveis

Esta pasta armazena arquivos de credenciais que **NÃO** devem ser commitados no Git.

## Arquivo: Client Secret MasterPalm Android

### Caminho completo

```
C:\Users\Pichau\apk_nathy\temp_naty\functions\credentials\client_secret_masterpalm_android.json
```

### Passo a passo

1. **Localize o arquivo baixado**
   - Normalmente em: `C:\Users\Pichau\Downloads\client_secret_950139833317-cjrntgmqa3umn010iv6v65rqfobr4cik.apps.googleusercontent.com.json`
   - Se tiver "(1)" no nome, é porque já existia outro com mesmo nome

2. **Renomeie o arquivo** (opcional, para facilitar):
   - De: `client_secret_950139833317-....json`
   - Para: `client_secret_masterpalm_android.json`

3. **Copie para a pasta de credenciais**
   - Origem: `C:\Users\Pichau\Downloads\client_secret_....json`
   - Destino: `C:\Users\Pichau\apk_nathy\temp_naty\functions\credentials\client_secret_masterpalm_android.json`

4. **Via Explorador de Arquivos**
   - Abra `C:\Users\Pichau\apk_nathy\temp_naty\functions\credentials`
   - Cole o arquivo JSON aqui
   - Confirme que o nome termina em `.json`

5. **Via terminal (PowerShell)**
   ```powershell
   Copy-Item "C:\Users\Pichau\Downloads\client_secret_950139833317-cjrntgmqa3umn010iv6v65rqfobr4cik.apps.googleusercontent.com.json" -Destination "C:\Users\Pichau\apk_nathy\temp_naty\functions\credentials\client_secret_masterpalm_android.json"
   ```

### Estrutura final

```
temp_naty/
└── functions/
    └── credentials/
        ├── .gitkeep
        ├── LEIA-ME.md
        └── client_secret_masterpalm_android.json   ← SEU ARQUIVO AQUI
```

### Uso nas Cloud Functions

Se precisar usar em alguma function (ex.: OAuth server-side):

```javascript
const credentials = require('./credentials/client_secret_masterpalm_android.json');
```

Ou via variável de ambiente (mais seguro em produção):

```javascript
const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
```

### Segurança

- Esta pasta está no `.gitignore` – o arquivo **não** será enviado ao Git
- Nunca compartilhe o arquivo nem faça commit
- Em produção, prefira variáveis de ambiente ou Secret Manager
