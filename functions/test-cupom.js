// Script de teste para validar a correção
const testCupom = {
  codigo: 'CUPOM-TEST123',
  desconto: 10,
  validade: '30/01/2025',
  usado: false,
  criadoEm: new Date().toISOString(), // ✅ Agora usa Date ao invés de serverTimestamp
  pedidoOrigem: 'pedido123',
};

console.log('✅ Cupom válido para array:');
console.log(JSON.stringify(testCupom, null, 2));
console.log('\n📝 Pode ser adicionado ao Firestore com arrayUnion()');
