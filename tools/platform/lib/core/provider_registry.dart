import '../exceptions/provider_exception.dart';

/// Instance-scoped dependency injection registry for platform providers.
class ProviderRegistry {
  ProviderRegistry();

  final Map<Type, Object> _instances = {};
  final Map<Type, Object Function()> _factories = {};

  void registerInstance<T extends Object>(T instance) {
    _instances[T] = instance;
    _factories.remove(T);
  }

  void registerFactory<T extends Object>(T Function() factory) {
    _factories[T] = factory;
    _instances.remove(T);
  }

  T resolve<T extends Object>() {
    final instance = _instances[T];
    if (instance != null) return instance as T;

    final factory = _factories[T];
    if (factory != null) return factory() as T;

    throw ProviderException(
      'Provider not registered',
      providerType: T.toString(),
    );
  }

  bool isRegistered<T extends Object>() =>
      _instances.containsKey(T) || _factories.containsKey(T);
}
