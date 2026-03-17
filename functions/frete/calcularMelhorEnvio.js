export const calcularMelhorEnvio = functions.https.onCall(async (data, context) => {
  const { token, origem, destino, peso, altura, largura, comprimento, servico } = data;

  const payload = {
    from: { postal_code: origem },
    to: { postal_code: destino },
    package: {
      weight: peso,
      height: altura,
      width: largura,
      length: comprimento
    },
    services: servico
  };

  const resp = await fetch(`https://www.melhorenvio.com.br/api/v2/me/shipment/calculate`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  return await resp.json();
});
