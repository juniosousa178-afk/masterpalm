# One-off: build loja_config_tema_pane.dart from loja_config_screen.dart
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
main = root / "lib/screens/loja_config_screen.dart"
out = root / "lib/screens/loja_config_tema_pane.dart"

lines = main.read_text(encoding="utf-8").splitlines(keepends=True)

# Accordion: lines 6012-6100 (1-based) -> 6011:6100
acc = "".join(lines[6011:6100])
acc = acc.replace("Widget _buildTemaAccordionSection(", "  Widget _buildTemaAccordionSection(")
acc = acc.replace("_temaAccordionOpenId", "_accordionOpenId")

# Main column: 6106-7013 (1-based) -> 6105:7013
col = "".join(lines[6105:7013])

H = "widget.host."

col = re.sub(
    r"onChanged:\s*\(c\)\s*=>\s*setState\(\(\)\s*=>\s*(_c[A-Za-z0-9]+)\s*=\s*c\s*\)",
    rf"onChanged: (c) => {H}_applyTemaColor(() => {H}\1 = c)",
    col,
)

col = col.replace(
    """onChanged: (c) => setState(() {
                    _cButtonSecondaryText = c;
                    _cButtonSecondaryBorder = c;
                  }),""",
    f"""onChanged: (c) => {H}_applyTemaColor(() {{
                    {H}_cButtonSecondaryText = c;
                    {H}_cButtonSecondaryBorder = c;
                  }}),""",
)

col = col.replace("_catalogColorFieldTema(", f"{H}_catalogColorFieldTema(")
col = col.replace("_catalogColorPaletteSuggestions()", f"{H}_catalogColorPaletteSuggestions()")
col = col.replace("_catalogMiniPreviewColors()", f"{H}_catalogMiniPreviewColors()")
col = col.replace("_miniPreviewStoreName()", f"{H}_miniPreviewStoreName()")
col = col.replace("_applyPreset(", f"{H}_applyPreset(")
col = col.replace("_confirmApplyVisualPalette", f"{H}_confirmApplyVisualPalette")

# CatalogColorFieldEditor color prop
col = re.sub(r"\bcolor:\s*(_c[A-Za-z0-9]+)\b", rf"color: {H}\1", col)

# BoxDecoration and other color: _c — second pass for lines not caught (nested)
col = re.sub(r"color:\s*(_c[A-Za-z0-9]+)\s*([,\)])", rf"color: {H}\1\2", col)

# TextStyle( ... color: _c
col = re.sub(r"(TextStyle\(\s*[^)]*color:\s*)(_c[A-Za-z0-9]+)", rf"\1{H}\2", col)
# withValues
col = re.sub(r"(_c[A-Za-z0-9]+)(\.withValues)", rf"{H}\1\2", col)
# Fix double host
col = col.replace(f"{H}{H}", H)

part = f"""part of 'loja_config_screen.dart';

class _PaneTemaWidget extends StatefulWidget {{
  const _PaneTemaWidget({{super.key, required this.host}});
  final _LojaConfigScreenState host;

  @override
  State<_PaneTemaWidget> createState() => _PaneTemaWidgetState();
}}

class _PaneTemaWidgetState extends State<_PaneTemaWidget> {{
  String? _accordionOpenId = 'tema_fundo';

{acc}
  @override
  Widget build(BuildContext context) {{
    final paletteSuggestions = widget.host._catalogColorPaletteSuggestions();
    final miniPreviewColors = widget.host._catalogMiniPreviewColors();
{col}  }}
}}
"""

out.write_text(part, encoding="utf-8")
print("Wrote", out)
