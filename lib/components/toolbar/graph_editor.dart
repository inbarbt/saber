import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_graph_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/graph/expression.dart';
import 'package:saber/data/graph/graph_spec.dart';
import 'package:saber/i18n/strings.g.dart';

/// Short labels for the templates, written as maths.
String graphTemplateLabel(GraphTemplate template) => switch (template) {
  .hyperbola => '1/x',
  .inverseSquare => '1/x²',
  .exponential => 'eˣ',
  .decay => 'e⁻ˣ',
  .logarithm => 'ln x',
  .squareRoot => '√x',
  .sine => 'sin x',
  .cosine => 'cos x',
  .tangent => 'tan x',
  .parabola => 'x²',
  .cubic => 'x³',
};

/// How the graph editor reads typed numbers.
abstract final class GraphSpecEditorNumbers {
  /// Reads a number the way it's typed: `-2`, `−2`, `1,5`, or a small
  /// expression like `pi/2` or `-2pi`. Null if it can't be read.
  static double? parse(String text) {
    final cleaned = text.trim().replaceAll('−', '-').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final plain = double.tryParse(cleaned);
    if (plain != null) return plain;
    final value = Formula.tryParse(cleaned)?.call(0);
    return value != null && value.isFinite ? value : null;
  }
}

/// Chooses a graph's function (template or formula), its x and y range,
/// and whether axes and asymptotes are shown. Shows a live preview.
class GraphSpecEditor extends StatefulWidget {
  const new({super.key, required this.initial, required this.onChanged});

  final GraphSpec initial;
  final ValueChanged<GraphSpec> onChanged;

  @override
  State<GraphSpecEditor> createState() => _GraphSpecEditorState();
}

class _GraphSpecEditorState extends State<GraphSpecEditor> {
  late var _spec = widget.initial;
  late final _formula = TextEditingController(text: widget.initial.formula);
  late final _xMin = TextEditingController(text: _fmt(widget.initial.xMin));
  late final _xMax = TextEditingController(text: _fmt(widget.initial.xMax));
  late final _yMin = TextEditingController(text: _fmt(widget.initial.yMin));
  late final _yMax = TextEditingController(text: _fmt(widget.initial.yMax));
  late final _domainMin = TextEditingController(
    text: _fmtOrEmpty(widget.initial.domainMin),
  );
  late final _domainMax = TextEditingController(
    text: _fmtOrEmpty(widget.initial.domainMax),
  );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  static String _fmtOrEmpty(double? v) => v == null ? '' : _fmt(v);

  static double? parseNumber(String text) => GraphSpecEditorNumbers.parse(text);

  @override
  void dispose() {
    for (final c in [
      _formula,
      _xMin,
      _xMax,
      _yMin,
      _yMax,
      _domainMin,
      _domainMax,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _update(GraphSpec spec) {
    setState(() => _spec = spec);
    widget.onChanged(spec);
  }

  void _updateRange() {
    final x0 = parseNumber(_xMin.text), x1 = parseNumber(_xMax.text);
    final y0 = parseNumber(_yMin.text), y1 = parseNumber(_yMax.text);
    if (x0 == null || x1 == null || y0 == null || y1 == null) return;
    if (x0 >= x1 || y0 >= y1) return;
    // An empty domain field means no limit on that side
    final d0 = parseNumber(_domainMin.text), d1 = parseNumber(_domainMax.text);
    if (_domainMin.text.trim().isNotEmpty && d0 == null) return;
    if (_domainMax.text.trim().isNotEmpty && d1 == null) return;
    if (d0 != null && d1 != null && d0 >= d1) return;
    _update(
      _spec.copyWith(
        xMin: x0,
        xMax: x1,
        yMin: y0,
        yMax: y1,
        domainMin: () => d0,
        domainMax: () => d1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = t.editor.graph;
    final formulaOk =
        !_spec.isFormula || Formula.tryParse(_spec.formula) != null;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Center(
          child: SizedBox(
            width: 200,
            height: 140,
            child: CustomPaint(
              painter: GraphPreviewPainter(
                _spec,
                ColorScheme.of(context).onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: .center,
          children: [
            for (final template in GraphTemplate.values)
              ChoiceChip(
                label: Text(graphTemplateLabel(template)),
                selected: _spec.template == template,
                onSelected: (_) => _update(
                  // A fresh template starts unshifted and unstretched
                  GraphSpec(
                    template: template,
                    xMin: _spec.xMin,
                    xMax: _spec.xMax,
                    yMin: _spec.yMin,
                    yMax: _spec.yMax,
                    domainMin: _spec.domainMin,
                    domainMax: _spec.domainMax,
                    showAxes: _spec.showAxes,
                    showAsymptotes: _spec.showAsymptotes,
                  ),
                ),
              ),
            ChoiceChip(
              label: Text(s.formula),
              selected: _spec.isFormula,
              onSelected: (_) => _update(
                _spec.copyWith(
                  clearTemplate: true,
                  formula: _formula.text.isEmpty ? '1/x' : _formula.text,
                ),
              ),
            ),
          ],
        ),
        if (_spec.isFormula) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _formula,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'y =',
              hintText: '(x^2-1)/(x-2)',
              errorText: formulaOk ? null : s.invalidFormula,
              border: const OutlineInputBorder(),
            ),
            onChanged: (text) =>
                _update(_spec.copyWith(clearTemplate: true, formula: text)),
          ),
        ],
        const SizedBox(height: 8),
        Text(s.axesRange, style: TextTheme.of(context).labelMedium),
        Row(
          children: [
            const Text('x '),
            Expanded(child: _numberField(_xMin)),
            const Text(' … '),
            Expanded(child: _numberField(_xMax)),
            const SizedBox(width: 16),
            const Text('y '),
            Expanded(child: _numberField(_yMin)),
            const Text(' … '),
            Expanded(child: _numberField(_yMax)),
          ],
        ),
        const SizedBox(height: 8),
        Text(s.domain, style: TextTheme.of(context).labelMedium),
        Row(
          children: [
            const Text('x '),
            Expanded(child: _numberField(_domainMin, hint: '−∞')),
            const Text(' … '),
            Expanded(child: _numberField(_domainMax, hint: '∞')),
          ],
        ),
        SwitchListTile(
          title: Text(s.axes),
          value: _spec.showAxes,
          onChanged: (v) => _update(_spec.copyWith(showAxes: v)),
        ),
        SwitchListTile(
          title: Text(s.asymptotes),
          value: _spec.showAsymptotes,
          onChanged: (v) => _update(_spec.copyWith(showAsymptotes: v)),
        ),
      ],
    );
  }

  /// A field for one number. It opens the full keyboard: the number pad
  /// on some keyboards (Samsung's among them) has no minus sign.
  Widget _numberField(TextEditingController controller, {String? hint}) =>
      TextField(
        controller: controller,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.visiblePassword,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(isDense: true, hintText: hint),
        onChanged: (_) => _updateRange(),
      );
}

/// Draws a small graph for previews and picker icons.
class GraphPreviewPainter extends CustomPainter {
  new(this.spec, this.color, {this.strokeWidth = 2});

  final GraphSpec spec;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final graph = GraphStroke(
      color: color,
      pressureEnabled: false,
      options: StrokeOptions(size: strokeWidth),
      pageIndex: 0,
      page: _previewPage,
      toolId: .shapePen,
      frame: Offset.zero & size,
      spec: spec,
    );
    final drawing = graph.drawing;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final thin = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = .stroke
      ..strokeWidth = 1;
    for (final (from, to) in drawing.axes) {
      canvas.drawLine(from, to, thin);
    }
    for (final (from, to) in drawing.asymptotes) {
      canvas.drawPath(
        dashPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..lineTo(to.dx, to.dy),
          dashArray: CircularIntervalList([4, 4]),
        ),
        thin,
      );
    }
    final curve = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = .round
      ..strokeCap = .round;
    for (final piece in drawing.curve) {
      canvas.drawPath(Path()..addPolygon(piece, false), curve);
    }
    canvas.restore();
  }

  static final _previewPage = EditorPage();

  @override
  bool shouldRepaint(GraphPreviewPainter old) =>
      old.spec != spec || old.color != color;
}
