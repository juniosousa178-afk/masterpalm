import 'dart:html' as html;

import 'package:flutter/material.dart';

void qaWebSyncLoginControllersIfNeeded({
  required TextEditingController login,
  required TextEditingController senha,
}) {
  for (final node in html.document.querySelectorAll('input')) {
    final input = node as html.InputElement;
    final value = input.value ?? '';
    if (value.isEmpty) continue;
    if (input.type == 'password') {
      senha.text = value;
    } else if (input.type == 'text' || input.type == 'email') {
      login.text = value;
    }
  }
}
