import 'dart:convert';

import 'package:saber/data/graph/graph_spec.dart';
import 'package:saber/data/prefs.dart';

/// The graph the shape pen draws next, as chosen in the shape picker.
abstract final class NewGraph {
  static GraphSpec get spec {
    final saved = stows.newGraphSpec.value;
    if (saved.isEmpty) {
      return const GraphSpec(template: GraphTemplate.hyperbola);
    }
    try {
      return GraphSpec.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } on FormatException {
      return const GraphSpec(template: GraphTemplate.hyperbola);
    }
  }

  static set spec(GraphSpec spec) =>
      stows.newGraphSpec.value = jsonEncode(spec.toJson());
}
