import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class DuesScreen extends StatelessWidget {
  const DuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';

    var receivable = 0.0;
    var payable = 0.0;
    for (final d in data.dues) {
      if (d.status == 'cancelled') continue;
      final remaining = d.amount - data.settledOf(d.id);
      if (remaining <= 0.005) continue;
      if (d.direction == 'receivable') {
        receivable += remaining;
      } else {
        payable += remaining;
      }
    }

    // Default view: unsettled (open + partial).
    final unsettled = data.dues.where((d) {
      final st = dueStatusFromSettled(d, data.settledOf(d.id));
      return st == 'open' || st == 'partial';
    }).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (receivable > 0 || payable > 0)
          Row(
            children: [
              if (receivable > 0)
                Expanded(child: StatCard(label: 'Receivable', amount: receivable, currency: currency, tone: StatTone.success, icon: Icons.arrow_downward)),
              if (receivable > 0 && payable > 0) const SizedBox(width: 12),
              if (payable > 0)
                Expanded(child: StatCard(label: 'Payable', amount: payable, currency: currency, tone: StatTone.danger, icon: Icons.arrow_upward)),
            ],
          ),
        const SizedBox(height: 12),
        if (unsettled.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(title: 'No unsettled dues'))
        else
          for (final d in unsettled)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(d.title),
                subtitle: Text('${d.direction == 'receivable' ? 'Receivable' : 'Payable'} · due ${formatDate(d.dueDate)}'),
                trailing: Text(formatMoney(d.amount - data.settledOf(d.id), currency),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
      ],
    );
  }
}
