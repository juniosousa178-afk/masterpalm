// M3.8 Sprint 2 — tokens do Design System MasterPalm (admin claro).
// Não altera engines de negócio.

import 'package:flutter/material.dart';

/// Paleta alinhada à Home / Vendas administrativas.
abstract final class MpColors {
  static const Color primary = Color(0xFF6366F1);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF0EA5E9);
  static const Color marketing = Color(0xFFEC4899);
  static const Color roleta = Color(0xFF8B5CF6);
  static const Color financeiro = Color(0xFF0D9488);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color chipBg = Color(0xFFF1F5F9);
}

abstract final class MpSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class MpRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
}

abstract final class MpType {
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: MpColors.ink,
    height: 1.25,
  );
  static const TextStyle section = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: MpColors.inkMuted,
    letterSpacing: 0.4,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: MpColors.ink,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: MpColors.inkMuted,
  );
  static const TextStyle kpiValue = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: MpColors.ink,
  );
  static const TextStyle kpiLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: MpColors.inkMuted,
  );
}
