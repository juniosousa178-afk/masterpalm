import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

String combinedDigest(List<int> bytes) => sha256.convert(bytes).toString();

Future<SignatureAlgorithm> algorithm() async => Ed25519();
