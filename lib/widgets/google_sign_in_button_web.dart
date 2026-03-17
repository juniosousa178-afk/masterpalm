// Widget do botão Google Sign-In para Web (GIS - renderButton).
// Evita o popup deprecado e problemas de COOP.
import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart'
    show
        GSIButtonConfiguration,
        GSIButtonSize,
        GSIButtonText,
        GSIButtonTheme,
        renderButton;

/// Botão nativo do Google Identity Services para web.
/// Evita popup deprecado e COOP. Use apenas quando kIsWeb.
Widget buildGoogleSignInButtonWeb() {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: renderButton(
      configuration: GSIButtonConfiguration(
        theme: GSIButtonTheme.filledBlue,
        size: GSIButtonSize.large,
        text: GSIButtonText.signinWith,
        locale: 'pt-BR',
      ),
    ),
  );
}
