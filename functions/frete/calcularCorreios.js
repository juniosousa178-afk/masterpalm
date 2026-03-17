import functions from "firebase-functions";
import axios from "axios";

export const calcularCorreios = functions.https.onCall(async (data, context) => {
  const { cepOrigem, cepDestino, peso, altura, largura, comprimento, declararValor, valorDeclarado, codigo } = data;

  const params = {
    nCdServico: codigo === "sedex" ? "04014" : "04510",
    sCepOrigem: cepOrigem,
    sCepDestino: cepDestino,
    nVlPeso: peso,
    nVlComprimento: comprimento,
    nVlAltura: altura,
    nVlLargura: largura,
    nVlDiametro: 0,
    sCdMaoPropria: "N",
    nVlValorDeclarado: declararValor ? valorDeclarado : 0,
    sCdAvisoRecebimento: "N"
  };

  const url = "http://ws.correios.com.br/calculador/CalcPrecoPrazo.aspx";

  const { data: xml } = await axios.get(url, { params });

  return xml;
});
