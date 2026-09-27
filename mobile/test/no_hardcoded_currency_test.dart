// A workspace keeps its books in one currency, and every screen must ask the
// workspace which. This scans the app's source so a hardcoded rupee can't slip
// back in through a new screen.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The only places allowed to name INR as a fallback: the catalogue, the
  // model that reads old workspaces with no currency field, and the controller
  // every screen asks.
  const allowed = {
    'lib/core/currency.dart',
    'lib/data/models.dart',
    'lib/state/workspace_controller.dart',
  };

  final banned = <String, RegExp>{
    'a baseCurrency fallback (use WorkspaceController.currency)': RegExp(r"baseCurrency\s*\?\?"),
    'a hardcoded rupee prefix (use currencySymbol)': RegExp(r"""prefixText:\s*['"]₹"""),
    'a hardcoded Rs symbol (use the currency spec)': RegExp(r"""symbol:\s*['"]Rs"""),
    'a fyStartMonth fallback (use WorkspaceController.fyStartMonth)': RegExp(r"fyStartMonth\s*\?\?\s*4"),
  };

  test('no screen assumes the rupee', () {
    final offences = <String>[];
    final files =
        Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final path = f.path.replaceAll('\\', '/');
      if (allowed.contains(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final e in banned.entries) {
          if (e.value.hasMatch(lines[i])) offences.add('$path:${i + 1}: ${e.key}');
        }
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}
