import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const _kHolder = '__mpOAuthReturn';
const _kKeys = ['code', 'state', 'error', 'error_description'];

/// Lê (uma vez) o retorno do Mercado Pago que o `index.html` tirou da URL de `/mp-oauth-callback`.
/// null = o script não correu (página sem o holder); mapa vazio = nada a concluir (ex.: refresh).
Map<String, String>? takeMpOAuthReturnParams() {
  final holder = globalContext.getProperty<JSAny?>(_kHolder.toJS);
  if (holder == null || !holder.typeofEquals('object')) return null;
  final obj = holder as JSObject;
  final out = <String, String>{};
  for (final k in _kKeys) {
    final v = obj.getProperty<JSAny?>(k.toJS);
    if (v != null && v.typeofEquals('string')) out[k] = (v as JSString).toDart;
  }
  globalContext.setProperty(_kHolder.toJS, null);
  return out;
}
