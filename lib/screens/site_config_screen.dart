// lib/screens/site_config_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/site_config_service.dart';

/// Tela para configurar o site de divulgação (links, contatos, download).
/// Apenas masterpalm26@gmail.com (programador) pode acessar.
class SiteConfigScreen extends StatefulWidget {
  const SiteConfigScreen({super.key});

  @override
  State<SiteConfigScreen> createState() => _SiteConfigScreenState();
}

class _SiteConfigScreenState extends State<SiteConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  late TextEditingController _apkDownloadUrl;
  late TextEditingController _appWebUrl;
  late TextEditingController _supportWhatsappUrl;
  late TextEditingController _instagramUrl;
  late TextEditingController _supportEmail;
  late TextEditingController _apkVersion;
  late TextEditingController _apkSize;
  late TextEditingController _apkReleaseDate;
  late TextEditingController _apkChangelog;

  @override
  void initState() {
    super.initState();
    _apkDownloadUrl = TextEditingController();
    _appWebUrl = TextEditingController();
    _supportWhatsappUrl = TextEditingController();
    _instagramUrl = TextEditingController();
    _supportEmail = TextEditingController();
    _apkVersion = TextEditingController();
    _apkSize = TextEditingController();
    _apkReleaseDate = TextEditingController();
    _apkChangelog = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _apkDownloadUrl.dispose();
    _appWebUrl.dispose();
    _supportWhatsappUrl.dispose();
    _instagramUrl.dispose();
    _supportEmail.dispose();
    _apkVersion.dispose();
    _apkSize.dispose();
    _apkReleaseDate.dispose();
    _apkChangelog.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final config = await SiteConfigService.load();
      _apkDownloadUrl.text = config.apkDownloadUrl;
      _appWebUrl.text = config.appWebUrl;
      _supportWhatsappUrl.text = config.supportWhatsappUrl;
      _instagramUrl.text = config.instagramUrl;
      _supportEmail.text = config.supportEmail;
      _apkVersion.text = config.apkVersion;
      _apkSize.text = config.apkSize;
      _apkReleaseDate.text = config.apkReleaseDate;
      _apkChangelog.text = config.apkChangelog;
    } catch (e) {
      _showSnack('Erro ao carregar: $e', isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final rootEmails = {'masterpalm26@gmail.com', 'masterpalm@gmail.com'};
    if (!rootEmails.contains(email.toLowerCase().trim())) {
      _showSnack('Acesso negado. Apenas conta root.', isError: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final config = SiteConfig(
        apkDownloadUrl: _apkDownloadUrl.text.trim(),
        appWebUrl: _appWebUrl.text.trim(),
        supportWhatsappUrl: _supportWhatsappUrl.text.trim(),
        instagramUrl: SiteConfig.normalizeInstagram(_instagramUrl.text),
        supportEmail: _supportEmail.text.trim(),
        apkVersion: _apkVersion.text.trim(),
        apkSize: _apkSize.text.trim(),
        apkReleaseDate: _apkReleaseDate.text.trim(),
        apkChangelog: _apkChangelog.text.trim(),
      );
      await SiteConfigService.save(config, updatedBy: email);
      _showSnack('Configurações salvas com sucesso!');
    } catch (e) {
      _showSnack('Erro ao salvar: $e', isError: true);
    } finally {
      setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final rootEmails = {'masterpalm26@gmail.com', 'masterpalm@gmail.com'};
    if (!rootEmails.contains(email.toLowerCase().trim())) {
      return Scaffold(
        appBar: AppBar(title: const Text('Config. do Site')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Acesso negado.\nApenas conta root pode configurar o site.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Site'),
        actions: [
          if (!_loading)
            IconButton(
              icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              onPressed: _saving ? null : _save,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSection('Links principais', [
                      _buildField('URL Download APK', _apkDownloadUrl, 'https://.../masterpalm.apk', keyboardType: TextInputType.url),
                      _buildField('URL AppWeb', _appWebUrl, 'https://app.mastepalm.com.br', keyboardType: TextInputType.url),
                    ]),
                    const SizedBox(height: 24),
                    _buildSection('Contatos', [
                      _buildField('WhatsApp (wa.me/55...)', _supportWhatsappUrl, 'https://wa.me/5511999999999', keyboardType: TextInputType.url),
                      _buildField('Instagram (usuário ou URL)', _instagramUrl, 'masterpalm ou https://instagram.com/masterpalm', keyboardType: TextInputType.url),
                      _buildField('E-mail de suporte (aparece no Para: ao clicar)', _supportEmail, 'suporte@mastepalm.com.br', keyboardType: TextInputType.emailAddress),
                    ]),
                    const SizedBox(height: 24),
                    _buildSection('Info do APK', [
                      _buildField('Versão', _apkVersion, '1.0.0'),
                      _buildField('Tamanho', _apkSize, '~25 MB'),
                      _buildField('Data de lançamento', _apkReleaseDate, '2025'),
                      _buildChangelogField(),
                    ]),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                      label: Text(_saving ? 'Salvando...' : 'Salvar configurações'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          filled: true,
        ),
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
      ),
    );
  }

  Widget _buildChangelogField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _apkChangelog,
        decoration: const InputDecoration(
          labelText: 'Novidades da atualização (exibidas ao usuário)',
          hintText: 'Ex:\n? Correção de bugs\n? Melhorias de desempenho\n? Nova funcionalidade X',
          border: OutlineInputBorder(),
          filled: true,
          alignLabelWithHint: true,
        ),
        maxLines: 5,
        minLines: 2,
        textInputAction: TextInputAction.newline,
      ),
    );
  }
}
