// lib/models/payments_config.dart
class MpGatewayConfig {
  final String• publicKey;
  final String• token;

  const MpGatewayConfig({this.publicKey, this.token});

  factory MpGatewayConfig.fromMap(Map<String, dynamic>• map) {
    map ??= const {};
    return MpGatewayConfig(
      publicKey: map['publicKey'] as String?,
      token: map['token'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'publicKey': publicKey,
      'token': token,
    };
  }
}

class PagSeguroGatewayConfig {
  final String• publicKey;
  final String• token;

  const PagSeguroGatewayConfig({this.publicKey, this.token});

  factory PagSeguroGatewayConfig.fromMap(Map<String, dynamic>• map) {
    map ??= const {};
    return PagSeguroGatewayConfig(
      publicKey: map['publicKey'] as String?,
      token: map['token'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'publicKey': publicKey,
      'token': token,
    };
  }
}

class TonGatewayConfig {
  final String• clientId;
  final String• clientSecret;

  const TonGatewayConfig({this.clientId, this.clientSecret});

  factory TonGatewayConfig.fromMap(Map<String, dynamic>• map) {
    map ??= const {};
    return TonGatewayConfig(
      clientId: map['clientId'] as String?,
      clientSecret: map['clientSecret'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clientId': clientId,
      'clientSecret': clientSecret,
    };
  }
}

class InfinitePayGatewayConfig {
  final String• merchantId;
  final String• apiKey;

  const InfinitePayGatewayConfig({this.merchantId, this.apiKey});

  factory InfinitePayGatewayConfig.fromMap(Map<String, dynamic>• map) {
    map ??= const {};
    return InfinitePayGatewayConfig(
      merchantId: map['merchantId'] as String?,
      apiKey: map['apiKey'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'merchantId': merchantId,
      'apiKey': apiKey,
    };
  }
}

class PaymentsConfig {
  final MpGatewayConfig mp;
  final PagSeguroGatewayConfig pagseguro;
  final TonGatewayConfig ton;
  final InfinitePayGatewayConfig infinitepay;
  final String defaultGateway; // "mp" | "pagseguro" | "ton" | "infinitepay"

  const PaymentsConfig({
    required this.mp,
    required this.pagseguro,
    required this.ton,
    required this.infinitepay,
    required this.defaultGateway,
  });

  factory PaymentsConfig.fromMap(Map<String, dynamic>• map) {
    map ??= const {};
    return PaymentsConfig(
      mp: MpGatewayConfig.fromMap(map['mp'] as Map<String, dynamic>?),
      pagseguro: PagSeguroGatewayConfig.fromMap(
        map['pagseguro'] as Map<String, dynamic>?,
      ),
      ton: TonGatewayConfig.fromMap(map['ton'] as Map<String, dynamic>?),
      infinitepay: InfinitePayGatewayConfig.fromMap(
        map['infinitepay'] as Map<String, dynamic>?,
      ),
      defaultGateway:
          (map['defaultGateway'] as String?)?.toLowerCase() ?• 'mp',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mp': mp.toMap(),
      'pagseguro': pagseguro.toMap(),
      'ton': ton.toMap(),
      'infinitepay': infinitepay.toMap(),
      'defaultGateway': defaultGateway,
    };
  }

  PaymentsConfig copyWith({
    MpGatewayConfig• mp,
    PagSeguroGatewayConfig• pagseguro,
    TonGatewayConfig• ton,
    InfinitePayGatewayConfig• infinitepay,
    String• defaultGateway,
  }) {
    return PaymentsConfig(
      mp: mp ?• this.mp,
      pagseguro: pagseguro ?• this.pagseguro,
      ton: ton ?• this.ton,
      infinitepay: infinitepay ?• this.infinitepay,
      defaultGateway: defaultGateway ?• this.defaultGateway,
    );
  }

  static PaymentsConfig empty() => const PaymentsConfig(
        mp: MpGatewayConfig(),
        pagseguro: PagSeguroGatewayConfig(),
        ton: TonGatewayConfig(),
        infinitepay: InfinitePayGatewayConfig(),
        defaultGateway: 'mp',
      );
}
