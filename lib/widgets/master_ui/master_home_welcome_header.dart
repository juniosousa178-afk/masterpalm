import 'package:flutter/material.dart';

/// Topo premium da Home — saudação e marca (só apresentação).
class MasterHomeWelcomeHeader extends StatelessWidget {
  const MasterHomeWelcomeHeader({
    super.key,
    required this.greeting,
    required this.userName,
    this.tagline = 'MasterPalm · sua loja em um só lugar',
  });

  final String greeting;
  final String userName;
  final String tagline;

  static const Color _primary = Color(0xFF6366F1);
  static const Color _accent = Color(0xFF818CF8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  _primary.withOpacity(0.45),
                  const Color(0xFF312E81).withOpacity(0.85),
                ]
              : [_primary, _accent],
        ),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(isDark ? 0.2 : 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.88),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  userName.isEmpty ? 'MasterPalm' : userName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  tagline,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.82),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
