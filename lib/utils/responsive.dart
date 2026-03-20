import 'package:flutter/material.dart';

/// Breakpoints para layout responsivo
const double kMobileBreakpoint = 600;
const double kTabletBreakpoint = 900;
const double kDesktopBreakpoint = 1200;

/// Largura máxima do conteúdo em desktop
const double kMaxContentWidth = 1200;

bool isMobile(BuildContext context) =>
    MediaQuery.of(context).size.width < kTabletBreakpoint;

bool isTablet(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  return w >= kTabletBreakpoint && w < kDesktopBreakpoint;
}

bool isDesktop(BuildContext context) =>
    MediaQuery.of(context).size.width >= kDesktopBreakpoint;

/// Retorna número de colunas ideal para grids baseado na largura
int responsiveGridCount(BuildContext context, {int mobile = 2, int tablet = 3, int desktop = 4}) {
  if (isDesktop(context)) return desktop;
  if (isTablet(context)) return tablet;
  return mobile;
}

/// Widget que builda diferente para mobile vs desktop
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) mobile;
  final Widget Function(BuildContext context)• tablet;
  final Widget Function(BuildContext context)• desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopBreakpoint && desktop != null) {
          return desktop!(context);
        }
        if (constraints.maxWidth >= kTabletBreakpoint && tablet != null) {
          return tablet!(context);
        }
        return mobile(context);
      },
    );
  }
}
