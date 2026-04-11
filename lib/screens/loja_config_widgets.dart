// Widgets auxiliares da Loja Config (mesma library que loja_config_screen.dart).
// Extraídos para reduzir blast radius do ficheiro principal; comportamento idêntico.

part of 'loja_config_screen.dart';

/// Campo de imagem com botão "Escolher imagem" (galeria), preview e opção de remover.
class _ImageFieldWithGallery extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Future<String?> Function() onPickImage;

  const _ImageFieldWithGallery({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onPickImage,
  });

  @override
  State<_ImageFieldWithGallery> createState() => _ImageFieldWithGalleryState();
}

class _ImageFieldWithGalleryState extends State<_ImageFieldWithGallery> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    final hasImage = url.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                decoration: InputDecoration(
                  labelText: '${widget.label} (URL ou use Galeria)',
                  border: const OutlineInputBorder(),
                  hintText: 'Link ou escolha pela galeria',
                ),
                onChanged: (_) {
                  setState(() {});
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final urlResult = await widget.onPickImage();
                    if (urlResult != null && context.mounted) {
                      widget.controller.text = urlResult;
                      setState(() {});
                      widget.onChanged();
                    }
                  },
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Escolher imagem'),
                ),
                if (hasImage) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () {
                      widget.controller.clear();
                      setState(() {});
                      widget.onChanged();
                    },
                    child: const Text('Remover'),
                  ),
                ],
              ],
            ),
          ],
        ),
        if (hasImage) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 80,
              width: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  size: 32,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  const _Section({
    required this.title,
    this.subtitle,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.92),
                            height: 1.4,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null)
                  Flexible(
                    child: action!,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: child),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Colors.blue.shade700 : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: selected ? Colors.blue.shade50 : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? Colors.blue.shade700 : Colors.grey.shade400,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: selected ? Colors.blue.shade700 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
