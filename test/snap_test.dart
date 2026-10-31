import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/shape_library.dart';
import 'package:saber/data/tools/snap.dart';

void main() {
  FlavorConfig.setup();
  final page = EditorPage();
  const tol = 10.0;

  Stroke raw(Offset a, Offset b) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 2),
    pageIndex: 0,
    page: page,
    toolId: .shapePen,
  )..addPoints([a, b]);

  Stroke shape(LibraryShape kind, Rect r) =>
      ShapeLibrary.strokeFor(raw(r.topLeft, r.bottomRight), kind);

  CircleStroke circle(Offset c, double r) => CircleStroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 2),
    pageIndex: 0,
    page: page,
    toolId: .shapePen,
    center: c,
    radius: r,
  );

  group('a dragged point', () {
    final square = shape(.rectangle, const Rect.fromLTWH(100, 100, 100, 100));
    final targets = SnapFeatures.of([square]);

    test('snaps to a nearby corner', () {
      final r = Snap.point(const Offset(205, 96), targets, tol);
      expect(r.value, const Offset(200, 100));
      expect(r.guides.whereType<SnapPointGuide>(), isNotEmpty);
    });

    test('snaps to the middle of a side', () {
      final r = Snap.point(const Offset(148, 103), targets, tol);
      expect(r.value, const Offset(150, 100));
    });

    test('snaps onto a side when no corner is near', () {
      final r = Snap.point(const Offset(125, 106), targets, tol);
      expect(r.value, const Offset(125, 100));
    });

    test('lines up with a centre from afar', () {
      final r = Snap.point(const Offset(153, 400), targets, tol);
      expect(r.value, const Offset(150, 400));
    });

    test('stays put when nothing is near', () {
      final r = Snap.point(const Offset(400, 400), targets, tol);
      expect(r.value, const Offset(400, 400));
      expect(r.guides, isEmpty);
    });

    test('makes a line tangent to a circle', () {
      final c = SnapFeatures.of([circle(const Offset(300, 300), 50)]);
      const anchor = Offset(100, 300);
      final tangents = Snap.tangentPoints(anchor, const Offset(300, 300), 50);
      final r = Snap.point(
        tangents.first + const Offset(4, 3),
        c,
        tol,
        anchor: anchor,
      );
      expect((r.value - tangents.first).distance, lessThan(1e-9));
      // The line from the anchor touches the circle at a right angle
      final toCenter = const Offset(300, 300) - r.value;
      final along = r.value - anchor;
      expect(
        (toCenter.dx * along.dx + toCenter.dy * along.dy).abs(),
        lessThan(1e-6),
      );
    });
  });

  group('a moved selection', () {
    test('centre snaps onto centre', () {
      final moving = SnapFeatures.of([
        shape(.rectangle, const Rect.fromLTWH(0, 0, 40, 40)),
      ]);
      final targets = SnapFeatures.of([circle(const Offset(300, 200), 60)]);
      // Dragged so its centre (20,20) lands near (300,200)
      final r = Snap.move(moving, targets, const Offset(284, 176), tol);
      expect(r.value, const Offset(280, 180));
    });

    test('centre lines up with a symmetry line', () {
      final moving = SnapFeatures.of([
        shape(.triangle, const Rect.fromLTWH(0, 0, 40, 40)),
      ]);
      final targets = SnapFeatures.of([
        shape(.rectangle, const Rect.fromLTWH(200, 0, 100, 60)),
      ]);
      final r = Snap.move(moving, targets, const Offset(227, 400), tol);
      expect(r.value.dy, 400);
      // The triangle's corners or centre now line up with something on
      // the rectangle, across
      expect(r.value.dx, isNot(227));
      expect(r.guides, isNotEmpty);
    });

    test('a side snaps tangent to a circle', () {
      final moving = SnapFeatures.of([
        shape(.rectangle, const Rect.fromLTWH(0, 1000, 40, 40)),
      ]);
      final targets = SnapFeatures.of([circle(const Offset(500, 500), 50)]);
      // Moves the square's top side to y = 553, just below the circle
      // (bottom at 550), with its middle under the centre.
      final r = Snap.move(moving, targets, const Offset(487, -447), tol);
      final top = 1000 + r.value.dy;
      expect(top, closeTo(550, 1e-6));
    });

    test('gaps even out between shapes in a row', () {
      final targets = SnapFeatures.of([
        shape(.rectangle, const Rect.fromLTWH(0, 0, 40, 40)),
        shape(.rectangle, const Rect.fromLTWH(90, 0, 40, 40)),
      ]);
      final moving = SnapFeatures.of([
        shape(.rectangle, const Rect.fromLTWH(0, 300, 40, 40)),
      ]);
      // To the right of the second, gap of 53 instead of 50
      final r = Snap.move(moving, targets, const Offset(183, -295), tol);
      expect(r.value.dx, 180);
      expect(r.guides.whereType<SnapLineGuide>().length, greaterThan(1));
    });
  });

  test('handwriting gives nothing to snap to', () {
    final scribble = Stroke(
      color: Colors.black,
      pressureEnabled: true,
      options: StrokeOptions(size: 2),
      pageIndex: 0,
      page: page,
      toolId: .fountainPen,
    )..addPoints(const [Offset.zero, Offset(30, 10), Offset(60, 0)]);
    expect(SnapFeatures.of([scribble]).isEmpty, isTrue);
  });
}
