from pathlib import Path
changed=0
for p in Path('lib').rglob('*.dart'):
    t=p.read_text(encoding='utf-8')
    n=t.replace('•','?')
    if n!=t:
        p.write_text(n,encoding='utf-8',newline='')
        changed+=1
print('changed',changed)
