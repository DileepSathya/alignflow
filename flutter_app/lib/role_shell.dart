import 'package:flutter/material.dart';

/// Shared workspace frame for every role. Role pages supply their navigation
/// and content while this widget owns the common responsive shell.
class RoleShell extends StatelessWidget {
  final Widget sidebar;
  final Widget content;
  final String title;
  const RoleShell(
      {super.key,
      required this.sidebar,
      required this.content,
      required this.title});

  static const navigationWidth = 190.0;
  static const contentWidth = 1240.0;
  static const pagePadding = EdgeInsets.fromLTRB(20, 28, 20, 24);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 900;
    return Scaffold(
      drawer: compact ? Drawer(child: sidebar) : null,
      body: Row(children: [
        if (!compact) SizedBox(width: navigationWidth, child: sidebar),
        Expanded(
            child: Column(children: [
          if (compact)
            Builder(
                builder: (context) => AppBar(
                    title: Text(title),
                    backgroundColor: Colors.white,
                    leading: IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer()))),
          Expanded(child: content),
        ])),
      ]),
    );
  }
}
