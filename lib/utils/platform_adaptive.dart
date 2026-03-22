// Decisões de layout e interação entre plataformas (paridade UX).
//
// Regras de negócio, persistência e serviços NÃO entram aqui — apenas:
// - breakpoints (delegados a [responsive.dart])
// - affordance: toque vs ponteiro, chrome largo vs compacto
//
// A mesma janela estreita no desktop nativo é tratada como "compacta" que nem mobile,
// evitando divergência só por `kIsWeb` ou `Platform`.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'responsive.dart';

export 'responsive.dart';

/// True quando o build corre no navegador (web mobile ou web desktop).
bool get appIsWeb => kIsWeb;

/// Layout compacto: largura &lt; [kTabletBreakpoint] (telefone, web mobile, janela estreita).
/// Sinônimo documentado de [isMobile] para leitura em código de paridade.
bool isLayoutCompact(BuildContext context) => isMobile(context);

/// Layout com largura de tablet/desktop (≥ [kTabletBreakpoint]).
bool isLayoutMediumOrWide(BuildContext context) => !isMobile(context);

/// Chrome pensado para ponteiro (setas laterais, áreas clicáveis amplas no eixo X).
/// Não implica plataforma nativa — só largura disponível.
bool usePointerFirstChrome(BuildContext context) => !isMobile(context);

/// Galeria de imagens: mostrar setas de navegação em layouts largos; foco em deslize no compacto.
bool showGalleryArrowNavigation(BuildContext context) => !isMobile(context);

/// Swipe/toque como interação principal (mobile APK, web mobile, janela estreita).
bool isTouchFirstInteraction(BuildContext context) => isMobile(context);
