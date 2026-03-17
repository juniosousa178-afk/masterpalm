import 'package:firebase_auth/firebase_auth.dart';
import 'plano_service.dart';
import 'package:hive/hive.dart';

Future<void> refreshPermissoesLocais() async {
  final email = FirebaseAuth.instance.currentUser?.email;
  if (email == null) return;

  final plano = await PlanoService.getPlano(email); // lê do Firestore
  final sessao = Hive.box('sessao');
  await sessao.put('permissoes', plano);
}
