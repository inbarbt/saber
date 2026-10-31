import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/graph/graph_spec.dart';

void main() {
  group('templates:', () {
    test('a shifted hyperbola has its asymptotes at h and k', () {
      const spec = GraphSpec(template: GraphTemplate.hyperbola, h: 1, k: 2);
      expect(spec.verticalAsymptotes(), [1]);
      expect(spec.horizontalAsymptotes(), [2]);
      expect(spec.function!(2), closeTo(3, 1e-12)); // 1/(2-1)+2
    });

    test('tangent repeats its asymptotes across the range', () {
      const spec = GraphSpec(template: GraphTemplate.tangent);
      final poles = spec.verticalAsymptotes();
      expect(poles, hasLength(4)); // ±π/2, ±3π/2 inside [-5, 5]
      expect(poles.first, closeTo(-3 * pi / 2, 1e-9));
    });

    test('a parabola has no asymptotes', () {
      const spec = GraphSpec(template: GraphTemplate.parabola);
      expect(spec.verticalAsymptotes(), isEmpty);
      expect(spec.horizontalAsymptotes(), isEmpty);
    });

    test('the curve breaks at the asymptote and climbs toward it', () {
      const spec = GraphSpec(template: GraphTemplate.hyperbola);
      final pieces = spec.curvePieces();
      expect(pieces, hasLength(2));
      final left = pieces.first, right = pieces.last;
      expect(left.last.dx, lessThan(0));
      expect(right.first.dx, greaterThan(0));
      // Next to the asymptote the curve is far off the top/bottom of the view
      expect(left.last.dy, lessThan(spec.yMin));
      expect(right.first.dy, greaterThan(spec.yMax));
    });

    test('the logarithm starts at its domain edge', () {
      const spec = GraphSpec(template: GraphTemplate.logarithm);
      final pieces = spec.curvePieces();
      expect(pieces, hasLength(1));
      expect(pieces.single.first.dx, closeTo(0, 1e-3));
      expect(pieces.single.first.dy, lessThan(spec.yMin));
    });

    test('dragging the stretch handle sets a and b', () {
      const spec = GraphSpec(template: GraphTemplate.hyperbola);
      final moved = spec.withHandle(1, const Offset(2, 3));
      // Handle sits at u = 1: x = h + 1/b, y = k + a·1
      expect(moved.b, closeTo(0.5, 1e-12));
      expect(moved.a, closeTo(3, 1e-12));
      expect(moved.handlePoints()[1].dx, closeTo(2, 1e-12));
      expect(moved.handlePoints()[1].dy, closeTo(3, 1e-12));
    });

    test('dragging the move handle shifts the asymptotes', () {
      const spec = GraphSpec(template: GraphTemplate.exponential);
      final moved = spec.withHandle(0, const Offset(-1, 2));
      expect(moved.h, -1);
      expect(moved.horizontalAsymptotes(), [2]);
    });
  });

  group('formulas:', () {
    test('1/x: vertical asymptote at 0 and horizontal at 0', () {
      const spec = GraphSpec(formula: '1/x');
      final poles = spec.verticalAsymptotes();
      expect(poles, hasLength(1));
      expect(poles.single, closeTo(0, 1e-6));
      expect(spec.horizontalAsymptotes(), [0]);
      expect(spec.curvePieces(), hasLength(2));
    });

    test('(x^2-1)/(x-2): a pole at 2 and no horizontal asymptote', () {
      const spec = GraphSpec(formula: '(x^2-1)/(x-2)');
      final poles = spec.verticalAsymptotes();
      expect(poles, hasLength(1));
      expect(poles.single, closeTo(2, 1e-6));
      expect(spec.horizontalAsymptotes(), isEmpty);
    });

    test('1/x^2: a pole without a sign change', () {
      const spec = GraphSpec(formula: '1/x^2');
      final poles = spec.verticalAsymptotes();
      expect(poles, hasLength(1));
      expect(poles.single, closeTo(0, 1e-4));
    });

    test('a steep but continuous function has no poles', () {
      const spec = GraphSpec(formula: 'x^3', yMin: -1, yMax: 1);
      expect(spec.verticalAsymptotes(), isEmpty);
      expect(spec.curvePieces(), hasLength(1));
    });

    test('sin(x) has no horizontal asymptote', () {
      expect(
        const GraphSpec(formula: 'sin(x)').horizontalAsymptotes(),
        isEmpty,
      );
    });

    test('an unreadable formula draws nothing', () {
      expect(const GraphSpec(formula: '2+').curvePieces(), isEmpty);
    });
  });

  test('save and load keep everything', () {
    const spec = GraphSpec(
      template: GraphTemplate.decay,
      a: 2,
      b: -0.5,
      h: 1,
      k: -1,
      xMin: -3,
      xMax: 7,
      yMin: -2,
      yMax: 4,
      showAsymptotes: false,
    );
    expect(GraphSpec.fromJson(spec.toJson()), spec);
    const formula = GraphSpec(formula: '1/(x-1)');
    expect(GraphSpec.fromJson(formula.toJson()), formula);
  });
}
