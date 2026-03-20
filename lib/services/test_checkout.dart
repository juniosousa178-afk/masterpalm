// lib/screens/test_checkout.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class TestCheckout extends StatefulWidget {
  const TestCheckout({super.key});

  @override
  State<TestCheckout> createState() => _TestCheckoutState();
}

class _TestCheckoutState extends State<TestCheckout> {
  String _result = '';
  bool _loading = false;

  Future<void> _criarPreferencia() async {
    setState(() {
      _loading = true;
      _result = '';
    });

    try {
      // 🔧 Ajuste aqui se sua loja tiver outro slug/ID no Firestore:
      const lojaId = 'masterpalm';

      // Use um orderId único para cada teste
      final orderId = DateTime.now().millisecondsSinceEpoch.toString();

      // 1) Cria/atualiza o pedido mínimo exigido pela Function
      final pedidoRef =
          FirebaseFirestore.instance.doc('lojas/$lojaId/pedidos/$orderId');

      await pedidoRef.set({
        'email': 'comprador@teste.com',
        'customerName': 'Comprador Teste',
        'items': [
          {
            'productId': 'p1',
            'name': 'Produto 1',
            'qty': 1,
            'price': 10.50,
            'imageUrl': ''
          },
        ],
      }, SetOptions(merge: true));

      // 2) Chama a Function (use o rewrite do Hosting)
      // Se você configurou o rewrite no firebase.json, pode usar a URL do Hosting:
      final url =
          Uri.parse('https://masterpalm-58c46.web.app/checkout/preference');

      // Se preferir a URL direta da Function na mesma região:
      // final url = Uri.parse(
      //   'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/createPreference',
      // );

      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'lojaId': lojaId, 'orderId': orderId}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _result = '✅ Preferência criada!\n\n'
              'orderId: $orderId\n\n'
              'init_point:\n${data['init_point']}';
        });
      } else {
        setState(() => _result = '❌ Erro (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      setState(() => _result = '⚠️ Erro: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teste Checkout Mercado Pago'),
        backgroundColor: Colors.black87,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _loading ? null : _criarPreferencia,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Criar preferência'),
            ),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _result,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
