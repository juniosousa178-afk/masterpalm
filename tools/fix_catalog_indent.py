from pathlib import Path

p = Path(__file__).resolve().parent.parent / "lib/screens/loja_config_screen.dart"
lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
out = []
i = 0
prefix18 = " " * 18
prefix16 = " " * 16
while i < len(lines):
    line = lines[i]
    if line.startswith(f"{prefix18}_catalogColorField("):
        out.append(line)
        i += 1
        while i < len(lines):
            l = lines[i]
            st = l.lstrip()
            if st.startswith("label:") and l.startswith(prefix16):
                out.append(f"{' ' * 20}{st}")
            elif st.startswith("color:") and l.startswith(prefix16):
                out.append(f"{' ' * 20}{st}")
            elif st.startswith("onChanged:") and l.startswith(prefix16):
                out.append(f"{' ' * 20}{st}")
            elif st.startswith("),") and l.startswith("              ") and not l.startswith(prefix18):
                out.append(f"{prefix18}{st}")
                i += 1
                break
            else:
                out.append(l)
            i += 1
        continue
    out.append(line)
    i += 1
p.write_text("".join(out), encoding="utf-8")
print("done")
