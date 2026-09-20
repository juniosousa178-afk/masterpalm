import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../../../services/loja_id_service.dart';
import '../../../widgets/app_help_icon_button.dart';
import '../consignment_errors.dart';
import '../consignment_feature_flag.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import 'consignment_form_screen.dart';
import 'consignment_details_screen.dart';
import 'consignment_reseller_history_screen.dart';

class ConsignmentListScreen extends StatefulWidget {
  const ConsignmentListScreen({super.key});

  @override
  State<ConsignmentListScreen> createState() => _ConsignmentListScreenState();
}

class _ConsignmentListScreenState extends State<ConsignmentListScreen> {
  String? _lojaId;
  bool _loading = true;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final lojaId = await LojaIdService.get();
      final enabled =
          lojaId != null && lojaId.trim().isNotEmpty && await ConsignmentFeatureFlag.isEnabled(lojaId);
      if (!mounted) return;
      setState(() {
        _lojaId = lojaId;
        _enabled = enabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: const Text('Consignados'),
        actions: [
          if (_enabled && _lojaId != null)
            IconButton(
              tooltip: 'Histórico por revendedor',
              icon: const Icon(Icons.people_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConsignmentResellerHistoryScreen(lojaId: _lojaId!),
                ),
              ),
            ),
          const AppHelpIconButton(),
        ],
      ),
      floatingActionButton: _enabled && _lojaId != null
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConsignmentFormScreen(lojaId: _lojaId!),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nova consignação'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_enabled
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'O módulo de consignados não está habilitado nesta loja.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _error != null
                  ? Center(child: Text(_error!))
                  : StreamBuilder<List<ConsignmentDoc>>(
                      stream: ConsignmentService.watchConsignments(_lojaId!),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(
                            child: Text(ConsignmentException.userMessage(
                                'SERVER', snap.error.toString())),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final items = snap.data!;
                        if (items.isEmpty) {
                          return const Center(
                            child: Text('Nenhuma consignação ainda.'),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final c = items[i];
                            return Card(
                              child: ListTile(
                                title: Text(c.resellerName),
                                subtitle: Text(
                                  '${c.totalItemsSent} pç · ${consignmentMoney.format(c.potentialGrossAmount)}',
                                ),
                                trailing: ConsignmentStatusChip(c.status),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ConsignmentDetailsScreen(
                                      lojaId: _lojaId!,
                                      consignmentId: c.id,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
