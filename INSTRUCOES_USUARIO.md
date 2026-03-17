# 📱 Instruções para Corrigir o Problema de Publicação

## 🔴 PROBLEMA

Quando você clica em "Publicar Catálogo", as alterações não aparecem no catálogo web porque:
- O app está salvando na loja `loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2`
- Mas o web carrega da loja `nathy-pratas-e-folheados`

## ✅ SOLUÇÃO SIMPLES

### Opção 1: Limpar Cache do App (RECOMENDADO)

**Android:**
1. Ir em **Configurações** do celular
2. **Apps** → **MasterPalm**
3. **Armazenamento**
4. **Limpar cache** (NÃO limpar dados!)
5. Voltar ao app
6. Fazer **logout**
7. Fazer **login** novamente com `natypolylopes1997@gmail.com`
8. Agora está pronto! ✅

**iOS:**
1. Desinstalar o app
2. Reinstalar
3. Fazer login com `natypolylopes1997@gmail.com`

### Opção 2: Forçar Reload no App

No app, vá em qualquer tela e:
1. Faça **logout**
2. Faça **login** novamente
3. O sistema vai recarregar tudo do Firestore

---

## 🧪 COMO TESTAR SE FUNCIONOU

Após limpar o cache:

1. **Fazer login** com `natypolylopes1997@gmail.com`

2. **Abrir "Configurações da Loja"**

3. **Observar no console/log** (se tiver acesso):
   ```
   ✅ Deve aparecer: store_id: nathy-pratas-e-folheados
   ❌ NÃO deve aparecer: loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2
   ```

4. **Fazer uma alteração pequena** (ex: mudar nome da loja)

5. **Clicar em "Publicar Catálogo"**

6. **Observar no console**:
   ```
   🚀 [PUBLICAR] PUBLICANDO CATÁLOGO
   LojaId: nathy-pratas-e-folheados  ← DEVE SER ESTE!
   ```

7. **Abrir o catálogo web**:
   ```
   https://mastepalm.com.br/loja/nathy-pratas-e-folheados
   ```

8. **Verificar se aparece**:
   - ✅ Logo (se você configurou)
   - ✅ Banners
   - ✅ Produtos

---

## ❓ POR QUE ISSO ACONTECEU?

O app guarda informações no **cache local** (Hive) para funcionar offline.

Quando corrigimos o Firestore, o cache local ainda tinha o valor antigo:
```
Cache: loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2  ← antigo
Firestore: nathy-pratas-e-folheados  ← novo ✅
```

Ao limpar o cache, o app vai buscar do Firestore e pegar o valor correto!

---

## 🎯 DEPOIS DE CORRIGIR

### URLs para compartilhar:

**Naty:**
```
https://mastepalm.com.br/loja/nathy-pratas-e-folheados
```

**MasterPalm:**
```
https://mastepalm.com.br/loja/masterpalm
```
ou
```
https://mastepalm.com.br/
```

### Como publicar corretamente:

1. **Fazer alterações** em Configurações da Loja
2. **Salvar Rascunho** (botão verde) - salva draft
3. **Publicar Catálogo** (botão azul) - copia draft → config
4. **Abrir catálogo web** para verificar

---

## 📞 SE NÃO FUNCIONAR

Se após limpar o cache ainda não funcionar:

1. Enviar print do console mostrando:
   ```
   🚀 [PUBLICAR] PUBLICANDO CATÁLOGO
   LojaId: ???
   ```

2. O desenvolvedor vai verificar se há outro problema

---

*Instruções criadas em 29/12/2025*
