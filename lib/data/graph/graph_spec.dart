import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:saber/data/graph/expression.dart';

/// Ready-made function shapes. Each is drawn as `a·g(b·(x−h)) + k`, where
/// g is the template's base function, so the same handles work for all:
/// (h, k) moves the graph, a and b stretch it.
enum GraphTemplate {
  hyperbola, // 1/u
  inverseSquare, // 1/u²
  exponential, // e^u
  decay, // e^-u
  logarithm, // ln u
  squareRoot, // √u
  sine, // sin u
  cosine, // cos u
  tangent, // tan u
  parabola, // u²
  cubic; // u³

  double base(double u) => switch (this) {
    hyperbola => 1 / u,
    inverseSquare => 1 / (u * u),
    exponential => math.exp(u),
    decay => math.exp(-u),
    logarithm => math.log(u),
    squareRoot => math.sqrt(u),
    sine => math.sin(u),
    cosine => math.cos(u),
    tangent => math.tan(u),
    parabola => u * u,
    cubic => u * u * u,
  };

  /// Where the stretch handle sits on the base curve (u, g(u)).
  /// Chosen so g(u) isn't zero and u isn't zero.
  double get handleU => switch (this) {
    logarithm => math.e,
    sine => math.pi / 2,
    cosine => math.pi,
    tangent => math.pi / 4,
    _ => 1,
  };

  /// Base-curve u values of vertical asymptotes, repeating every
  /// [verticalPeriod] if that's not null.
  List<double> get verticalAsymptotesU => switch (this) {
    hyperbola || inverseSquare || logarithm => const [0],
    tangent => const [math.pi / 2],
    _ => const [],
  };

  double? get verticalPeriod => this == tangent ? math.pi : null;

  /// Whether the base curve levels off at g = 0 (a horizontal asymptote).
  bool get hasHorizontalAsymptote =>
      this == hyperbola ||
      this == inverseSquare ||
      this == exponential ||
      this == decay;

  static GraphTemplate? fromName(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// What a graph shows: a template with parameters, or a typed formula,
/// over a range of x and y.
@immutable
class GraphSpec {
  const new({
    this.template,
    this.formula = '',
    this.a = 1,
    this.b = 1,
    this.h = 0,
    this.k = 0,
    this.xMin = -5,
    this.xMax = 5,
    this.yMin = -5,
    this.yMax = 5,
    this.showAxes = true,
    this.showAsymptotes = true,
  });

  /// Null for a typed formula.
  final GraphTemplate? template;
  final String formula;
  final double a, b, h, k;
  final double xMin, xMax, yMin, yMax;
  final bool showAxes, showAsymptotes;

  bool get isFormula => template == null;

  /// How many points to sample across the x range.
  static const samples = 400;

  /// The function drawn, or null if the formula can't be read.
  GraphFunction? get function {
    final t = template;
    if (t != null) return (x) => a * t.base(b * (x - h)) + k;
    return Formula.tryParse(formula);
  }

  double get xSpan => xMax - xMin;
  double get ySpan => yMax - yMin;

  /// x positions of vertical asymptotes inside the x range.
  List<double> verticalAsymptotes() {
    final t = template;
    if (t == null) return _detectVerticalAsymptotes();
    if (b == 0) return const [];
    final result = <double>[];
    final period = t.verticalPeriod;
    for (final u0 in t.verticalAsymptotesU) {
      if (period == null) {
        final x = h + u0 / b;
        if (x > xMin && x < xMax) result.add(x);
      } else {
        // x = h + (u0 + n·period)/b, for every n landing in range
        final xPeriod = (period / b).abs();
        final first = h + u0 / b;
        var n = ((xMin - first) / xPeriod).ceil();
        for (var x = first + n * xPeriod; x < xMax; x = first + ++n * xPeriod) {
          if (x > xMin) result.add(x);
        }
      }
    }
    return result..sort();
  }

  /// y positions of horizontal asymptotes inside the y range.
  List<double> horizontalAsymptotes() {
    final t = template;
    if (t != null) {
      return t.hasHorizontalAsymptote && k > yMin && k < yMax ? [k] : const [];
    }
    final f = function;
    if (f == null) return const [];
    final result = <double>{};
    for (final sign in const [1.0, -1.0]) {
      final far = [1e3, 1e4, 1e5].map((m) => f(sign * m * xSpan)).toList();
      if (far.any((y) => !y.isFinite)) continue;
      final settled =
          (far[1] - far[0]).abs() < 1e-2 * ySpan &&
          (far[2] - far[1]).abs() < 1e-3 * ySpan;
      if (!settled) continue;
      final y = far[2];
      if (y > yMin && y < yMax) result.add(_snap(y));
    }
    return result.toList()..sort();
  }

  /// Rounds to a small fraction of the visible height, so values that are
  /// only approaching an asymptote (like 1/x far out) land on it.
  double _snap(double y) {
    final step = ySpan * 1e-4;
    return (y / step).round() * step + 0.0;
  }

  List<double> _detectVerticalAsymptotes() {
    final f = function;
    if (f == null) return const [];
    final result = <double>[];
    final step = xSpan / samples;
    var prevX = xMin;
    var prevY = f(prevX);
    for (int i = 1; i <= samples; i++) {
      final x = xMin + i * step;
      final y = f(x);
      if (_looksLikePole(prevY, y)) {
        final pole = _refinePole(f, prevX, x);
        if (pole != null) result.add(pole);
      }
      prevX = x;
      prevY = y;
    }
    // A pole sitting exactly on a sample shows up in both neighbouring gaps.
    final merged = <double>[];
    for (final pole in result) {
      if (merged.isEmpty || (pole - merged.last).abs() > xSpan * 1e-6) {
        merged.add(pole);
      }
    }
    return merged;
  }

  /// A sign change between two large values, or a jump to infinity.
  bool _looksLikePole(double y0, double y1) {
    if (y0.isInfinite || y1.isInfinite) return true;
    if (!y0.isFinite || !y1.isFinite) return false;
    final big = 2 * ySpan;
    return y0.sign != y1.sign && (y0.abs() > big || y1.abs() > big) ||
        (y1 - y0).abs() > 50 * ySpan;
  }

  /// Narrows a suspected pole between [x0] and [x1]. Returns null if the
  /// function stays bounded (a steep but continuous part, not a pole).
  double? _refinePole(GraphFunction f, double x0, double x1) {
    var lo = x0, hi = x1;
    final flo = f(lo), fhi = f(hi);
    if (flo.isFinite && fhi.isFinite && flo.sign != fhi.sign) {
      // A sign change through a pole: 1/f has a root there.
      var slo = flo.sign;
      for (int i = 0; i < 60; i++) {
        final mid = (lo + hi) / 2;
        final fm = f(mid);
        if (fm.isInfinite) return mid;
        if (!fm.isFinite) break;
        if (fm.sign == slo) {
          lo = mid;
          slo = fm.sign;
        } else {
          hi = mid;
        }
      }
    } else {
      // No sign change (like 1/x²): close in on where |f| is largest.
      for (int i = 0; i < 80; i++) {
        final m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
        final a1 = f(m1).abs(), a2 = f(m2).abs();
        if (a1.isInfinite) return m1;
        if (a2.isInfinite) return m2;
        if (a1 > a2) {
          hi = m2;
        } else {
          lo = m1;
        }
      }
    }
    final x = (lo + hi) / 2;
    final near = math.max(f(lo).abs(), f(hi).abs());
    return !near.isFinite || near > 1e3 * ySpan ? x : null;
  }

  /// The curve as pieces of (x, y) points, broken at asymptotes and gaps in
  /// the domain. Extra points are added close to vertical asymptotes, so the
  /// curve really climbs toward them.
  List<List<Offset>> curvePieces() {
    final f = function;
    if (f == null || xSpan <= 0 || ySpan <= 0) return const [];
    final poles = verticalAsymptotes();

    final xs = <double>[
      for (int i = 0; i <= samples; i++) xMin + i * xSpan / samples,
      for (final pole in poles)
        for (final d in const [1e-2, 3e-3, 1e-3, 3e-4, 1e-4, 1e-5, 1e-6]) ...[
          pole - d * xSpan,
          pole + d * xSpan,
        ],
      // Edges of a domain, e.g. √(x−h) or ln(x−h)
      if (template == GraphTemplate.squareRoot ||
          template == GraphTemplate.logarithm)
        for (final d in const [1e-2, 1e-3, 1e-4, 1e-6])
          h + (b == 0 ? 0 : d * xSpan / b.sign),
    ]..retainWhere((x) => x >= xMin && x <= xMax);
    xs.sort();

    // Far outside the visible range, points only need to say "off the top"
    final ceiling = yMax + 2 * ySpan, floor = yMin - 2 * ySpan;

    final pieces = <List<Offset>>[];
    var current = <Offset>[];
    var poleIndex = 0;
    double? prevX;
    for (final x in xs) {
      // Crossed a vertical asymptote since the last point
      while (poleIndex < poles.length && poles[poleIndex] <= x) {
        if (prevX != null && poles[poleIndex] > prevX) {
          if (current.length >= 2) pieces.add(current);
          current = <Offset>[];
        }
        poleIndex++;
      }
      prevX = x;

      final y = f(x);
      if (!y.isFinite) {
        if (current.length >= 2) pieces.add(current);
        current = <Offset>[];
        continue;
      }
      current.add(Offset(x, y.clamp(floor, ceiling)));
    }
    if (current.length >= 2) pieces.add(current);
    return pieces;
  }

  /// Where the move handle (h, k) and stretch handle sit, in graph
  /// coordinates. Empty for formulas.
  List<Offset> handlePoints() {
    final t = template;
    if (t == null || b == 0) return const [];
    final u = t.handleU;
    return [Offset(h, k), Offset(h + u / b, k + a * t.base(u))];
  }

  /// This graph with handle [index] (see [handlePoints]) dragged to [point]
  /// in graph coordinates.
  GraphSpec withHandle(int index, Offset point) {
    final t = template;
    if (t == null) return this;
    if (index == 0) {
      return copyWith(h: point.dx, k: point.dy);
    }
    final u = t.handleU;
    var dx = point.dx - h;
    if (dx.abs() < xSpan * 1e-3) dx = xSpan * 1e-3 * (dx.isNegative ? -1 : 1);
    final newB = u / dx;
    final g = t.base(u);
    final newA = g == 0 ? a : (point.dy - k) / g;
    return copyWith(a: newA, b: newB);
  }

  GraphSpec copyWith({
    GraphTemplate? template,
    bool clearTemplate = false,
    String? formula,
    double? a,
    double? b,
    double? h,
    double? k,
    double? xMin,
    double? xMax,
    double? yMin,
    double? yMax,
    bool? showAxes,
    bool? showAsymptotes,
  }) => GraphSpec(
    template: clearTemplate ? null : template ?? this.template,
    formula: formula ?? this.formula,
    a: a ?? this.a,
    b: b ?? this.b,
    h: h ?? this.h,
    k: k ?? this.k,
    xMin: xMin ?? this.xMin,
    xMax: xMax ?? this.xMax,
    yMin: yMin ?? this.yMin,
    yMax: yMax ?? this.yMax,
    showAxes: showAxes ?? this.showAxes,
    showAsymptotes: showAsymptotes ?? this.showAsymptotes,
  );

  Map<String, dynamic> toJson() => {
    if (template != null) 'gt': template!.name,
    if (formula.isNotEmpty) 'gf': formula,
    'ga': a,
    'gb': b,
    'gh': h,
    'gk': k,
    'gx0': xMin,
    'gx1': xMax,
    'gy0': yMin,
    'gy1': yMax,
    'gax': showAxes,
    'gas': showAsymptotes,
  };

  factory fromJson(Map<String, dynamic> json) {
    double d(String key, double fallback) => switch (json[key]) {
      (final num v) => v.toDouble(),
      _ => fallback,
    };
    return GraphSpec(
      template: GraphTemplate.fromName(json['gt'] as String?),
      formula: json['gf'] as String? ?? '',
      a: d('ga', 1),
      b: d('gb', 1),
      h: d('gh', 0),
      k: d('gk', 0),
      xMin: d('gx0', -5),
      xMax: d('gx1', 5),
      yMin: d('gy0', -5),
      yMax: d('gy1', 5),
      showAxes: json['gax'] as bool? ?? true,
      showAsymptotes: json['gas'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GraphSpec &&
      other.template == template &&
      other.formula == formula &&
      other.a == a &&
      other.b == b &&
      other.h == h &&
      other.k == k &&
      other.xMin == xMin &&
      other.xMax == xMax &&
      other.yMin == yMin &&
      other.yMax == yMax &&
      other.showAxes == showAxes &&
      other.showAsymptotes == showAsymptotes;

  @override
  int get hashCode => Object.hash(
    template,
    formula,
    a,
    b,
    h,
    k,
    xMin,
    xMax,
    yMin,
    yMax,
    showAxes,
    showAsymptotes,
  );
}
