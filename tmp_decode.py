import base64
s="Clpwcm9qZWN0cy9tYXN0ZXJwYWxtLTU4YzQ2L2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy9jYW1wYW5oYXNfc29ydGVpb3MpbmRlGeVzL18QARoJCgVhdGI2YRABGgskB2RhdGFGaW0QARoOCgpkYXRhSW5pY2lvEAEaDAoIX19uYW1lX18QAQ"
pad = '=' * (-len(s) % 4)
b=base64.b64decode(s+pad)
print('len',len(b))

def dump_after(kw, span=80, after=24):
    kb=kw.encode('utf-8')
    i=b.find(kb)
    print('\nKW',kw,'idx',i)
    if i==-1:
        return
    start=max(0,i-30); end=min(len(b),i+span)
    sn=b[start:end]
    print('window_hex', sn.hex())
    j=i+len(kb)
    print('after_hex', b[j:j+after].hex())

for kw in ['ativa','dataInicio','dataFim','campanhas_sorteio','__name__']:
    dump_after(kw)
