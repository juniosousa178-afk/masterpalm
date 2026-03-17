import 'package:flutter/material.dart';


class InputField extends StatelessWidget {
final TextEditingController controller;
final String hint;
final bool obscure;
final TextInputType keyboard;
final Widget? suffix;
const InputField({super.key, required this.controller, required this.hint, this.obscure=false, this.keyboard=TextInputType.text, this.suffix});
@override
Widget build(BuildContext context){
return TextField(
controller: controller,
obscureText: obscure,
keyboardType: keyboard,
decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
);
}
}