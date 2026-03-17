// Exporta o botão Google para Web (renderButton) ou stub para mobile.
import 'package:flutter/widgets.dart';

import 'google_sign_in_button_web.dart'
    if (dart.library.io) 'google_sign_in_button_stub.dart' as impl;

/// Botão Google Sign-In: GIS renderButton no web, placeholder no mobile.
/// Use apenas quando [kIsWeb].
Widget buildGoogleSignInButtonWeb() => impl.buildGoogleSignInButtonWeb();
