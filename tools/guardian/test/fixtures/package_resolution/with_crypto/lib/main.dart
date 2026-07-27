import 'package:crypto/crypto.dart';

String digestSha256(List<int> bytes) => sha256.convert(bytes).toString();
