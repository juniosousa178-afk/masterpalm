import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ConfigPinScreen extends StatefulWidget {
  const ConfigPinScreen({super.key});

  @override
  State<ConfigPinScreen> createState() => _ConfigPinScreenState();
}

class _ConfigPinScreenState extends State<ConfigPinScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _novoPinController = TextEditingController();
  final TextEditingController _confirmarPinController = TextEditingController();

  Future<void> _salvarNovoPin() async {
    final novoPin = _novoPinController.text.trim();
    final confirmar = _confirmarPinController.text.trim();

    if (novoPin != confirmar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PINs não coincidem')),
      );
      return;
    }

    final box = await Hive.openBox('config');
    await box.put('pin_programador', novoPin);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN alterado com sucesso')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alterar PIN do Programador')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _novoPinController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Novo PIN'),
                validator: (value) =>
                    value!.isEmpty ? 'Digite o novo PIN' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmarPinController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar PIN'),
                validator: (value) => value!.isEmpty ? 'Confirme o PIN' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _salvarNovoPin();
                  }
                },
                child: const Text('Salvar'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
