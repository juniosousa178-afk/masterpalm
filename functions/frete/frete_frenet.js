// functions/frete_frenet.js
import functions from "firebase-functions";
import fetch from "node-fetch";

// ⚠️ Use sempre variáveis de ambiente para o token em produção
//   (functions.config() ou process.env)

export const calcularFrenet = functions.https.onCall(async (data, context) => {
  const {
    token,
    storeId,
    cepOrigem,
    cepDestino,
    peso,         // em Kg (ajustar se necessário)
    altura,
    largura,
    comprimento,
    valorProdutos,
  } = data;

  if (!token || !cepOrigem || !cepDestino) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Parâmetros insuficientes para calcular o frete via Frenet."
    );
  }

  const url = "https://api.frenet.com.br/shipping/quote";

  const body = {
    SellerCEP: cepOrigem,
    RecipientCEP: cepDestino,
    ShipmentInvoiceValue: valorProdutos,
    ShippingItemArray: [
      {
        Weight: peso,        // kg
        Length: comprimento, // cm
        Height: altura,
        Width: largura,
        Quantity: 1,
      },
    ],
  };

  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "token": token, // header do Frenet
    },
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new functions.https.HttpsError(
      "internal",
      `Erro ao consultar Frenet: ${resp.status} - ${text}`
    );
  }

  const json = await resp.json();

  // Aqui você pode filtrar serviços, aplicar taxa/manuseio, etc.
  return json;
});
