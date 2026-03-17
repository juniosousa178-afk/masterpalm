# OAuth Mercado Pago – Guia de Troubleshooting

## Erro: "O aplicativo não está pronto para se conectar a Mercado Pago"

Se esse erro aparece mesmo após configurar a URL de redirecionamento, siga este checklist:

---

### 1. URL de redirecionamento (Redirect URI)

No painel do Mercado Pago, em **Configurações avançadas** > **URLs de redirecionamento**, adicione **exatamente**:

```
https://mastepalm.com.br/mp-oauth-callback
```

- Sem barra no final
- Sem parâmetros
- HTTPS obrigatório

---

### 2. Configuração da aplicação como Marketplace

O OAuth para conectar vendedores exige que a aplicação esteja configurada para **Marketplace** ou **Authorization code**:

1. Acesse [Suas integrações](https://www.mercadopago.com.br/developers/panel/app)
2. Clique na sua aplicação > **Editar dados**
3. Em **Configurações básicas**:
   - **Pagamentos online**: Sim
   - **Plataforma**: Se houver opção "Marketplace" ou "Outra plataforma", selecione
   - **Produto**: Checkout Pro ou Checkout Transparente (conforme sua integração)

---

### 3. URL do site em produção

Preencha o campo **URL do site em produção** (opcional, mas recomendado):

```
https://mastepalm.com.br
```

---

### 4. Permissões da aplicação

Em **Configurações avançadas** > **Permissões da aplicação**, verifique:

- **Leitura**: ativada
- **Acesso offline**: ativada (necessária para refresh token)
- **Escrita**: ativada

---

### 5. Credenciais corretas

- **MP_APP_ID** = App ID / Número da aplicação (ex: 183024624)
- **MP_CLIENT_SECRET** = Chave secreta (Client Secret)

Configure os secrets no Firebase:

```powershell
firebase functions:secrets:set MP_APP_ID
firebase functions:secrets:set MP_CLIENT_SECRET
```

---

### 6. Deploy após alterações

Após qualquer alteração no painel do Mercado Pago ou no código:

```powershell
firebase deploy --only "hosting,functions"
```

---

### 7. Contato com o suporte

Se o erro persistir:

- [Suporte Mercado Pago Developers](https://www.mercadopago.com.br/developers/pt/support/center)
- Informe: App ID, tipo de integração (Marketplace/OAuth), e que a URL de redirecionamento já foi configurada
