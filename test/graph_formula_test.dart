import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/graph/expression.dart';

void main() {
  double eval(String formula, double x) => Formula.parse(formula)(x);

  test('arithmetic and precedence', () {
    expect(eval('1+2*3', 0), 7);
    expect(eval('(1+2)*3', 0), 9);
    expect(eval('2^3^2', 0), 512); // right-associative
    expect(eval('-x^2', 3), -9); // power before minus
    expect(eval('10/4/5', 0), 0.5);
  });

  test('x, constants and implicit multiplication', () {
    expect(eval('2x', 3), 6);
    expect(eval('3(x+1)', 1), 6);
    expect(eval('x(x-1)', 4), 12);
    expect(eval('pi', 0), closeTo(pi, 1e-12));
    expect(eval('π x', 2), closeTo(2 * pi, 1e-12));
    expect(eval('e^x', 1), closeTo(e, 1e-12));
  });

  test('functions', () {
    expect(eval('sin(x)', pi / 2), closeTo(1, 1e-12));
    expect(eval('sin x', pi / 2), closeTo(1, 1e-12));
    expect(eval('ln(e)', 0), closeTo(1, 1e-12));
    expect(eval('log(100)', 0), closeTo(2, 1e-12));
    expect(eval('sqrt(x)', 9), 3);
    expect(eval('|x|', -4), 4);
    expect(eval('abs(x-5)', 2), 3);
    expect(eval('x sin(x)', pi / 2), closeTo(pi / 2, 1e-12));
  });

  test('1/x and rational functions give infinities and signs correctly', () {
    expect(eval('1/x', 0.001), closeTo(1000, 1e-9));
    expect(eval('1/x', -0.001), closeTo(-1000, 1e-9));
    expect(eval('(x^2-1)/(x-2)', 3), 8);
  });

  test('cube root of a negative number', () {
    expect(eval('x^(1/3)', -8), closeTo(-2, 1e-9));
  });

  test('bad formulas are reported, not crashed on', () {
    expect(Formula.tryParse(''), isNull);
    expect(Formula.tryParse('2+'), isNull);
    expect(Formula.tryParse('(x+1'), isNull);
    expect(Formula.tryParse('y+1'), isNull);
    expect(Formula.tryParse('3 # 4'), isNull);
  });
}
