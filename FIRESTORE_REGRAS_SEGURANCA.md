# Regras Firestore - Documentação de Segurança

## Resumo das alterações aplicadas

As regras foram atualizadas para **produção** com foco em:
- Remoção de regras permissivas (`if true`)
- Validação de campos obrigatórios em writes públicos
- Proteção contra abuso e criação massiva
- Manutenção do funcionamento atual dos fluxos

---

## Coleções principais

### clientes
| Operação | Regra | Motivo |
|----------|-------|--------|
| **read** | `resource != null` | Login catálogo usa query por email |
| **create** | `isValidClienteCreate()` | Valida: nome (2-120 chars), email (5-128 chars), doc ≤ 25 campos |
| **update** | Admin OU mesmo email | Evita overwrite malicioso |
| **delete** | Apenas admin | |

### pedidos_temp / pedido_temp / temp_orders
| Operação | Regra | Motivo |
|----------|-------|--------|
| **read** | `resource != null` | Deep link checkout |
| **create** | `isValidPedidoTempCreate()` | Doc ≤ 35 campos; lojaId opcional na raiz |
| **update** | `request.resource.data.size() <= 35` | Checkout anônimo precisa atualizar |
| **delete** | `resource != null` | Usuário pode limpar carrinho |

### pre_pedidos
| Operação | Regra | Motivo |
|----------|-------|--------|
| **read** | `resource != null` | Cliente vê pedidos no perfil |
| **create** | `isValidPrePedidoCreate()` | Valida: lojaId, cliente.email, itens (1-50), total (0-999999) |
| **update/delete** | Apenas admin | |

### pedidos_pendentes
| Operação | Regra | Motivo |
|----------|-------|--------|
| **read** | `resource != null` | Status pagamento / retorno URL |
| **create** | `isValidPedidoPendenteCreate()` | Valida: tipo, cliente.email, itens, total |
| **update** | Admin ou signed-in | |
| **delete** | Apenas admin | |

### cupons_clientes
| Operação | Regra | Motivo |
|----------|-------|--------|
| **read** | `resource != null` | Exibir cupons no catálogo |
| **create** | `isValidCupomClienteCreate()` | Valida: clienteId, codigo, doc ≤ 25 campos |
| **update/delete** | Apenas admin | |

### clientes_catalogo/{email}/cupons
| Operação | Regra | Motivo |
|----------|-------|--------|
| **read** | `resource != null` | Cliente vê cupons no perfil |
| **create** | `isValidClienteCatalogoCupomCreate()` | Roleta web: codigo, tipo, valor obrigatórios |
| **update/delete** | Apenas admin | |

---

## Limites e validações

| Coleção | Tamanho máximo doc | Campos obrigatórios |
|---------|--------------------|---------------------|
| clientes | 25 campos | nome, email |
| pre_pedidos | 45 campos | lojaId, cliente, itens, total |
| pedidos_temp | 35 campos | lojaId (quando em lojas/) |
| pedidos_pendentes | 50 campos | tipo, cliente, itens, total |
| cupons_clientes | 25 campos | clienteId, codigo |
| participantes | 20 campos | clienteId, valorCompra |

---

## Leitura pública mantida (necessária)

As seguintes coleções mantêm leitura pública para o catálogo web funcionar:
- **lojas** – listar lojas
- **config** – config do catálogo
- **categorias, subcategorias, produtos** – catálogo
- **cupons** – exibir no carrinho
- **canais_publicos** – canais disponíveis
- **campanhas_sorteio, participantes** – sorteios
- **campanhas_sorteio_config** – config da roleta
- **trackings** – validar no checkout
- **stores/products** – legado catálogo

---

## Recomendações futuras

1. **clientes**: Migrar login para Cloud Function para restringir leitura apenas a documentos do próprio usuário.
2. **cupons_clientes / participantes**: Implementar rate limiting via Cloud Function se houver abuso.
3. **pedidos_temp**: Monitorar volume de criações; considerar TTL ou limpeza automática.

---

## Deploy

```bash
firebase deploy --only firestore:rules
```

Regras aplicadas com sucesso em: **masterpalm-58c46**
