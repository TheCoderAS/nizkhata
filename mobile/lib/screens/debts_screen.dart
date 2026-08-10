import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';

    final visible = data.debts.where((d) => d.purpose != 'shared').toList();
    var theyOwe = 0.0;
    var youOwe = 0.0;
    for (final d in visible) {
      final o = data.outstandingOf(d.id);
      if (o <= 0.005) continue;
      if (d.direction == 'owed') {
        theyOwe += o;
      } else {
        youOwe += o;
      }
    }
    final owed = visible.where((d) => d.direction == 'owed').toList();
    final owe = visible.where((d) => d.direction == 'owe').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (theyOwe > 0 || youOwe > 0)
          Row(
            children: [
              if (theyOwe > 0)
                Expanded(child: StatCard(label: 'They owe you', amount: theyOwe, currency: currency, tone: StatTone.success, icon: Icons.arrow_downward)),
              if (theyOwe > 0 && youOwe > 0) const SizedBox(width: 12),
              if (youOwe > 0)
                Expanded(child: StatCard(label: 'You owe', amount: youOwe, currency: currency, tone: StatTone.danger, icon: Icons.arrow_upward)),
            ],
          ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(title: 'No debts yet'))
        else ...[
          if (owed.isNotEmpty) _group(context, 'They owe you', owed, data, currency),
          if (owe.isNotEmpty) _group(context, 'You owe', owe, data, currency),
        ],
      ],
    );
  }

  Widget _group(BuildContext context, String title, List debts, DataController data, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final d in debts)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt'),
              subtitle: Text(data.contactsById[d.contactId]?.name ?? '—'),
              trailing: Text(formatMoney(data.outstandingOf(d.id), currency),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}
