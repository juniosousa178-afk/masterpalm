import re
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "lib/screens/loja_config_screen.dart"
s = path.read_text(encoding="utf-8")

pat_multi = re.compile(
    r"_ColorPickerChip\(\s*\n\s*label:\s*([^\n]+),\s*\n\s*color:\s*([^\n,]+),\s*\n\s*onPick:\s*\(c\)\s*\{\s*\n\s*setState\(\(\)\s*\{\s*\n\s*_cButtonSecondaryText\s*=\s*c;\s*\n\s*_cButtonSecondaryBorder\s*=\s*c;\s*\n\s*\}\);\s*\n\s*_salvarRascunho\(validar:\s*false\);\s*\n\s*\},\s*\n\s*\),",
    re.MULTILINE,
)
s, n_multi = pat_multi.subn(
    r"_catalogColorField(\n                label: \1,\n                color: \2,\n                onChanged: (c) => setState(() {\n                    _cButtonSecondaryText = c;\n                    _cButtonSecondaryBorder = c;\n                  }),\n              ),",
    s,
)
print("multi", n_multi)

pat_single = re.compile(
    r"_ColorPickerChip\(\s*\n\s*label:\s*([^\n]+),\s*\n\s*color:\s*([^\n,]+),\s*\n\s*onPick:\s*\(c\)\s*\{\s*\n\s*setState\(\(\)\s*=>\s*([^;]+);\s*\n\s*_salvarRascunho\(validar:\s*false\);\s*\n\s*\},\s*\n\s*\),",
    re.MULTILINE,
)


def repl(m):
    return (
        f"_catalogColorField(\n                label: {m.group(1)},\n"
        f"                color: {m.group(2)},\n"
        f"                onChanged: (c) => setState(() => {m.group(3)}),),\n"
    )


s2, n_single = pat_single.subn(repl, s)
print("single", n_single)

path.write_text(s2, encoding="utf-8")
