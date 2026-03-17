// lib/utils/store_screen_route_observer.dart
// RouteObserver para telas que precisam reexecutar setup ao voltar (Vendas, Clientes).

import 'package:flutter/material.dart';

/// Observer para [RouteAware] em VendasScreen e ClientesScreen.
/// Permite que a tela reexecute _setup quando volta a ficar visível (didPopNext).
final RouteObserver<ModalRoute<void>> storeScreenRouteObserver =
    RouteObserver<ModalRoute<void>>();
