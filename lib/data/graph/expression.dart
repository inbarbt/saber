import 'dart:math' as math;

/// A function of x, parsed from a typed formula such as `1/x` or
/// `(x^2-1)/(x-2)`.
typedef GraphFunction = double Function(double x);

/// Why a formula couldn't be read, with where it went wrong.
class FormulaError implements Exception {
  const new(this.message, this.position);

  final String message;
  final int position;

  @override
  String toString() => 'FormulaError at $position: $message';
}

/// Reads formulas in x.
///
/// Supports numbers, `x`, `e`, `pi` (or `π`), `+ - * / ^`, brackets,
/// unary minus, implicit multiplication (`2x`, `3(x+1)`, `x sin(x)`),
/// and the functions sin, cos, tan, asin, acos, atan, sinh, cosh, tanh,
/// exp, ln, log (base 10), sqrt, abs.
abstract final class Formula {
  /// Parses [source], or throws a [FormulaError].
  static GraphFunction parse(String source) => _Parser(source).parse();

  /// Parses [source], or returns null if it isn't a valid formula.
  static GraphFunction? tryParse(String source) {
    try {
      return parse(source);
    } on FormulaError {
      return null;
    }
  }
}

const _functions = <String, double Function(double)>{
  'sin': math.sin,
  'cos': math.cos,
  'tan': math.tan,
  'asin': math.asin,
  'acos': math.acos,
  'atan': math.atan,
  'sinh': _sinh,
  'cosh': _cosh,
  'tanh': _tanh,
  'exp': math.exp,
  'ln': math.log,
  'log': _log10,
  'sqrt': math.sqrt,
  'abs': _abs,
};

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
double _tanh(double x) {
  final e2 = math.exp(2 * x);
  return e2.isInfinite ? 1 : (e2 - 1) / (e2 + 1);
}

double _log10(double x) => math.log(x) / math.ln10;
double _abs(double x) => x.abs();

class _Parser {
  new(String source)
    : _src = source
          .replaceAll('π', 'pi')
          .replaceAll('·', '*')
          .replaceAll('−', '-');

  final String _src;
  var _pos = 0;

  GraphFunction parse() {
    if (_src.trim().isEmpty) throw const FormulaError('empty formula', 0);
    final result = _sum();
    _skipSpaces();
    if (_pos < _src.length) {
      throw FormulaError('unexpected "${_src[_pos]}"', _pos);
    }
    return result;
  }

  void _skipSpaces() {
    while (_pos < _src.length && _src[_pos] == ' ') {
      _pos++;
    }
  }

  String? _peek() {
    _skipSpaces();
    return _pos < _src.length ? _src[_pos] : null;
  }

  bool _accept(String c) {
    if (_peek() == c) {
      _pos++;
      return true;
    }
    return false;
  }

  // sum := product (('+' | '-') product)*
  GraphFunction _sum() {
    var left = _product();
    while (true) {
      if (_accept('+')) {
        final a = left, b = _product();
        left = (x) => a(x) + b(x);
      } else if (_accept('-')) {
        final a = left, b = _product();
        left = (x) => a(x) - b(x);
      } else {
        return left;
      }
    }
  }

  // product := unary (('*' | '/' | implicit) unary)*
  GraphFunction _product() {
    var left = _unary();
    while (true) {
      if (_accept('*')) {
        final a = left, b = _unary();
        left = (x) => a(x) * b(x);
      } else if (_accept('/')) {
        final a = left, b = _unary();
        left = (x) => a(x) / b(x);
      } else if (_startsFactor()) {
        // Implicit multiplication: 2x, 3(x+1), x sin(x)
        final a = left, b = _power();
        left = (x) => a(x) * b(x);
      } else {
        return left;
      }
    }
  }

  bool _startsFactor() {
    final c = _peek();
    if (c == null) return false;
    return c == '(' || _isLetter(c) || _isDigit(c) || c == '.';
  }

  // unary := ('-' | '+') unary | power
  GraphFunction _unary() {
    if (_accept('-')) {
      final a = _unary();
      return (x) => -a(x);
    }
    if (_accept('+')) return _unary();
    return _power();
  }

  // power := atom ('^' unary)?   (right-associative, binds tighter than unary minus on the left)
  GraphFunction _power() {
    final base = _atom();
    if (_accept('^')) {
      final exponent = _unary();
      return (x) => _pow(base(x), exponent(x));
    }
    return base;
  }

  static double _pow(double base, double exponent) {
    // Odd roots of negative numbers, e.g. x^(1/3)
    if (base < 0 && exponent != exponent.roundToDouble()) {
      final inverse = 1 / exponent;
      if ((inverse - inverse.round()).abs() < 1e-9 && inverse.round().isOdd) {
        return -math.pow(-base, exponent).toDouble();
      }
    }
    return math.pow(base, exponent).toDouble();
  }

  GraphFunction _atom() {
    final c = _peek();
    if (c == null) throw FormulaError('formula ends too early', _pos);

    if (_accept('(')) {
      final inner = _sum();
      if (!_accept(')')) throw FormulaError('missing ")"', _pos);
      return inner;
    }
    if (_accept('|')) {
      final inner = _sum();
      if (!_accept('|')) throw FormulaError('missing "|"', _pos);
      return (x) => inner(x).abs();
    }
    if (_isDigit(c) || c == '.') return _number();
    if (_isLetter(c)) return _name();
    throw FormulaError('unexpected "$c"', _pos);
  }

  GraphFunction _number() {
    final start = _pos;
    while (_pos < _src.length && (_isDigit(_src[_pos]) || _src[_pos] == '.')) {
      _pos++;
    }
    final value = double.tryParse(_src.substring(start, _pos));
    if (value == null) throw FormulaError('bad number', start);
    return (_) => value;
  }

  GraphFunction _name() {
    final start = _pos;
    while (_pos < _src.length && _isLetter(_src[_pos])) {
      _pos++;
    }
    final word = _src.substring(start, _pos).toLowerCase();

    // A function name, possibly followed directly by more letters such as
    // "sinx": take the longest function name at the start.
    for (final name
        in _functions.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length))) {
      if (word.startsWith(name)) {
        _pos = start + name.length;
        final f = _functions[name]!;
        final GraphFunction argument;
        if (_peek() == '(') {
          argument = _atom();
        } else {
          // sin x, sinx, sin 2x
          argument = _power();
        }
        return (x) => f(argument(x));
      }
    }

    // Otherwise a run of constants and x, multiplied: "pix", "xe"
    _pos = start;
    GraphFunction? product;
    while (_pos < _src.length && _isLetter(_src[_pos])) {
      final GraphFunction factor;
      if (_src.startsWith('pi', _pos)) {
        factor = (_) => math.pi;
        _pos += 2;
      } else if (_src[_pos] == 'x' || _src[_pos] == 'X') {
        factor = (x) => x;
        _pos += 1;
      } else if (_src[_pos] == 'e') {
        factor = (_) => math.e;
        _pos += 1;
      } else {
        throw FormulaError('unknown name "${_src[_pos]}"', _pos);
      }
      final previous = product;
      product = previous == null ? factor : (x) => previous(x) * factor(x);
    }
    final result = product!;
    if (_peek() == '^') return result; // handled by _power's caller
    return result;
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isLetter(String c) {
    final u = c.toLowerCase().codeUnitAt(0);
    return u >= 97 && u <= 122;
  }
}
