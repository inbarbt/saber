import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/toolbar/pen_modal.dart';

void main() {
  test("level 3 is Saber's default of 0.5", () {
    expect(PenFeel.toValue(3), 0.5);
  });

  test('level 0 turns the effect off', () {
    expect(PenFeel.toValue(0), 0);
  });

  test('the top level stays below 1', () {
    expect(PenFeel.toValue(PenFeel.maxLevel), lessThan(1));
  });
}
