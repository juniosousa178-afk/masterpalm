import 'dart:html' as html;

void qaWebRegisterLoginTrigger(Future<void> Function() login) {
  (html.window as dynamic).__mpQaE2eLogin = () {
    login();
  };
}
