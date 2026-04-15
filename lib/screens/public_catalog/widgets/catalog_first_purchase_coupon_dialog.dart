// lib/screens/public_catalog/widgets/catalog_first_purchase_coupon_dialog.dart
// Modal elegante: cupom de primeira compra (cores configuráveis em uiColors).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog_cart_checkout_visual_config.dart';

Future<void> showCatalogFirstPurchaseCouponDialog({
  required BuildContext context,
  required CatalogFirstPurchaseCouponOffer offer,
  required VoidCallback onUseCoupon,
  required VoidCallback onDismiss,
}) {
  final s = offer.style;
  final copyAsFilled = s.copyButtonBackground.a > 0.02;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.38),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        elevation: 0,
        child: Material(
          color: s.background,
          elevation: 8,
          shadowColor: s.shadowColor.withOpacity(0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: s.borderColor.withOpacity(0.55),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onDismiss();
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: s.textColor.withOpacity(0.55),
                      ),
                      tooltip: 'Fechar',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 6),
                    child: Text(
                      offer.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        letterSpacing: -0.28,
                        color: s.titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      offer.body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        letterSpacing: 0.02,
                        color: s.textColor.withOpacity(0.94),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: s.codeBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: s.borderColor.withOpacity(0.28),
                        width: 1,
                      ),
                    ),
                    child: SelectableText(
                      offer.couponCode,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: s.codeTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: copyAsFilled
                            ? FilledButton(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: offer.couponCode),
                                  );
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.maybeOf(ctx)
                                        ?.showSnackBar(
                                      const SnackBar(
                                        content: Text('Cupom copiado!'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: s.copyButtonBackground,
                                  foregroundColor: s.copyButtonTextColor,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Copiar cupom',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.08,
                                  ),
                                ),
                              )
                            : OutlinedButton(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: offer.couponCode),
                                  );
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.maybeOf(ctx)
                                        ?.showSnackBar(
                                      const SnackBar(
                                        content: Text('Cupom copiado!'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: s.copyButtonTextColor,
                                  side: BorderSide(
                                    color: s.borderColor.withOpacity(0.55),
                                    width: 1.05,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Copiar cupom',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.08,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            onUseCoupon();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: s.useButtonBackground,
                            foregroundColor: s.useButtonTextColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Usar agora',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onDismiss();
                    },
                    child: Text(
                      'Fechar',
                      style: TextStyle(
                        color: s.textColor.withOpacity(0.62),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
