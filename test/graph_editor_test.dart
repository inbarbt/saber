import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/toolbar/graph_editor.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/graph/graph_spec.dart';
import 'package:saber/i18n/strings.g.dart';

void main() {
  FlavorConfig.setup();

  Future<List<GraphSpec>> pumpEditor(
    WidgetTester tester,
    GraphSpec initial,
  ) async {
    final changes = <GraphSpec>[];
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GraphSpecEditor(initial: initial, onChanged: changes.add),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('choosing a template changes the graph', (tester) async {
    final changes = await pumpEditor(
      tester,
      const GraphSpec(template: GraphTemplate.hyperbola),
    );
    await tester.tap(find.text('ln x'));
    await tester.pump();
    expect(changes.last.template, GraphTemplate.logarithm);
  });

  testWidgets('typing a formula changes the graph and flags bad ones', (
    tester,
  ) async {
    final changes = await pumpEditor(tester, const GraphSpec(formula: '1/x'));
    await tester.enterText(find.byType(TextField).first, '1/(x-2)');
    await tester.pump();
    expect(changes.last.formula, '1/(x-2)');
    expect(changes.last.isFormula, isTrue);

    await tester.enterText(find.byType(TextField).first, '1/(x-');
    await tester.pump();
    expect(find.text(t.editor.graph.invalidFormula), findsOneWidget);
  });

  testWidgets('the asymptotes switch', (tester) async {
    final changes = await pumpEditor(
      tester,
      const GraphSpec(template: GraphTemplate.hyperbola),
    );
    await tester.tap(find.text(t.editor.graph.asymptotes));
    await tester.pump();
    expect(changes.last.showAsymptotes, isFalse);
  });
}
