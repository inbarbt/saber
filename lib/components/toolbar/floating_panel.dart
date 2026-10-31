import 'package:flutter/material.dart';

/// A card that floats over the page, for a tool's settings or the
/// selection's actions. It never pushes the page aside.
class FloatingPanel extends StatelessWidget {
  const new({super.key, required this.child, this.padding = const .all(8)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Material(
      color: colorScheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
