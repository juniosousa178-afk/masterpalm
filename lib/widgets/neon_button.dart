import 'package:flutter/material.dart';
import '../themes/app_theme.dart';


class NeonButton extends StatelessWidget {
final String label;
final VoidCallback onPressed;
final bool secondary;
const NeonButton({super.key, required this.label, required this.onPressed, this.secondary = false});


@override
Widget build(BuildContext context) {
final bg = secondary • AppTheme.neonGreen : AppTheme.neonBlue;
return SizedBox(
width: double.infinity,
child: ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor: bg,
foregroundColor: Colors.black,
padding: const EdgeInsets.symmetric(vertical: 16),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
),
onPressed: onPressed,
child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
),
);
}
}