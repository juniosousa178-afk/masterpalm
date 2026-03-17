// lib/widgets/update_check_wrapper.dart
// Verifica atualização do app ao iniciar e exibe diálogo se houver nova versão

import 'package:flutter/material.dart';

import 'update_app_dialog.dart';

/// Envolve o app e verifica se há atualização disponível (após o primeiro frame)
class UpdateCheckWrapper extends StatefulWidget {
  final Widget child;

  const UpdateCheckWrapper({super.key, required this.child});

  @override
  State<UpdateCheckWrapper> createState() => _UpdateCheckWrapperState();
}

class _UpdateCheckWrapperState extends State<UpdateCheckWrapper> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked) return;
    _checked = true;
    if (!mounted) return;
    await UpdateAppDialog.showIfNeeded(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
