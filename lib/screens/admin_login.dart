import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  Future<void> _verificarPin() async {
    final pin = _pinController.text.trim();

    final configBox = await Hive.openBox('config');
    // Fallback apenas para primeira configuração; defina pin_programador em config (ex.: tela config_pin) em produção.
    final pinSalvo =
        configBox.get('pin_programador', defaultValue: '030419922009');

    if (pin != pinSalvo) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN incorreto')),
      );
      return;
    }

    setState(() => _loading = true);

    final sessao = await Hive.openBox('sessao');
    await sessao.put('usuario_logado', 'programador');
    await sessao.put('tipo_usuario', 'programador');
    await sessao.put('auth_context', 'admin');

    if (!mounted) return;
    // Rota /license não existe no app; usar /home para programador acessar o app.
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Acesso do Programador'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Digite o PIN do programador',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    labelStyle: const TextStyle(color: Colors.white),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    counterText: '',
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Informe o PIN' : null,
                ),
                const SizedBox(height: 24),
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            _verificarPin();
                          }
                        },
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Entrar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
