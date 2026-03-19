# Piloto Lote 1 — Resultados (preencher após execução)

Preencha cada seção após executar o roteiro de teste manual. Use este documento como evidência para a avaliação final e decisão sobre FASE 3.

---

## 1. GET verify

- **Resultado:** (ex.: PASSOU / FALHOU)
- **Evidência:** (ex.: "GET com token correto retornou 200 e corpo igual a hub.challenge" ou print/cópia do response)

---

## 2. POST válido

- **Resultado:** (ex.: PASSOU / FALHOU)
- **Evidência:** (ex.: "POST com payload Meta retornou 200" ou trecho do response/Postman)

---

## 3. Resposta no WhatsApp

- **Resultado:** (ex.: PASSOU / FALHOU)
- **Evidência:** (ex.: "Uma mensagem de resposta recebida no número de teste para 'oi'" ou print da conversa)

---

## 4. Loja correta por phone_number_id

- **Resultado:** (ex.: PASSOU / FALHOU)
- **Evidência:** (ex.: "Consulta 'quanto custa X' retornou produtos da loja Y conforme config" ou print da resposta)

---

## 5. Dedup por message.id

- **Resultado:** (ex.: PASSOU / FALHOU / N/A)
- **Evidência:** (ex.: "Dois POSTs idênticos → uma única resposta; log com skipped_duplicate no segundo" ou trecho de log)

---

## 6. Payload inválido

- **Resultado:** (ex.: PASSOU / FALHOU)
- **Evidência:** (ex.: "Body inválido retornou 200, sem mensagem enviada, sem req.body em log" ou trecho de log)

---

## 7. Logs sanitizados

- **Resultado:** (ex.: PASSOU / FALHOU)
- **Evidência:** (ex.: "Nenhuma linha de log contém req.body completo no handler WhatsApp" ou trecho de log do Cloud Logging)

---

## 8. Equivalência textual do rule-based

- **Resultado:** (ex.: PASSOU / FALHOU)
- **Evidência:** (ex.: "Textos comparados para saudação, preço, estoque, etc. idênticos ao baseline" ou lista de mensagens testadas e resultado)

---

## 9. Índice Enabled / fallback aceito

- **Resultado:** (ex.: PASSOU / PASSOU COM RESSALVA)
- **Evidência:** (ex.: "Índice canais em Enabled no Console" ou "Fallback por varredura usado; aceito para piloto")

---

## 10. Não conformidades encontradas

- **Crítica:** (listar ou "Nenhuma")
- **Média:** (listar ou "Nenhuma")
- **Leve:** (listar ou "Nenhuma")

---

## Assinatura do piloto (opcional)

- Data da execução:
- Responsável:
- Ambiente (ex.: projeto Firebase, região):

---

*Após preencher, use este documento como base para a Avaliação Final do Piloto e decisão sobre FASE 3.*
