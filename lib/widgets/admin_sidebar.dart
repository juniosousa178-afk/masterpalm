import 'package:flutter/material.dart';

class AdminSidebar extends StatelessWidget {
  final List<Widget> children;

  const AdminSidebar({super.key, this.children = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: children,
      ),
    );
  }
}

