import 'dart:math';

import 'package:flutter/widgets.dart';

/// Places the selection menu centred above [anchor] (the selection's
/// box, in the layout's coordinates), or below it if there's no room
/// above, and keeps it on screen.
class SelectionMenuLayout extends SingleChildLayoutDelegate {
  const new(this.anchor);

  final Rect anchor;

  /// Space between the selection box and the menu.
  static const gap = 36.0;

  /// Space kept between the menu and the edges.
  static const margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (anchor.center.dx - childSize.width / 2)
        .clamp(margin, max(margin, size.width - childSize.width - margin))
        .toDouble();
    final above = anchor.top - gap - childSize.height;
    final below = anchor.bottom + gap;
    final double y;
    if (above >= margin) {
      y = above;
    } else if (below + childSize.height <= size.height - margin) {
      y = below;
    } else {
      // A selection taller than the screen: keep the menu at the top.
      y = margin;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(SelectionMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}
