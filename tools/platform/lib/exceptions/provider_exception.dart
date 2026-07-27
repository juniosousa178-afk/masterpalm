import 'platform_exception.dart';

/// Raised when a provider is missing, misconfigured, or fails at runtime.
class ProviderException extends PlatformException {
  ProviderException(
    super.message, {
    super.cause,
    super.code,
    this.providerType,
  });

  final String? providerType;

  @override
  String toString() {
    final base = super.toString();
    if (providerType != null) return '$base [provider: $providerType]';
    return base;
  }
}
