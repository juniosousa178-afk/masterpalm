// lib/screens/home/widgets/web_landing_plan_card.dart
// Card de plano na landing web (mastepalm.com.br) — extraído de home_screen.

import 'package:flutter/material.dart';

/// Card de plano na landing web. Mesmos parâmetros e comportamento que _buildWebLandingPlanCard.
class WebLandingPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final Color color;
  final IconData icon;
  final String description;
  final List<String> bullets;
  final String• badge;
  final Color cardColor;
  final Color surfaceColor;

  const WebLandingPlanCard({
    super.key,
    required this.title,
    required this.price,
    required this.period,
    required this.color,
    required this.icon,
    required this.description,
    required this.bullets,
    this.badge,
    required this.cardColor,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha:0.5)),
              ),
              child: Text(
                badge!,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: surfaceColor,
                      ),
                    ),
                    Text(
                      '$price / $period',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(height: 12),
          ...bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.35),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

