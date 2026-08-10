import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (contacts.isEmpty) {
      return const EmptyView(title: 'No contacts', hint: 'People and businesses you transact with appear here.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = contacts[i];
        final net = data.positionOf(c.id).net;
        return ListTile(
          leading: EntityAvatar(name: c.name),
          title: Text(c.name),
          subtitle: Text(c.type == 'business' ? 'Business' : 'Person'),
          trailing: net.abs() < 0.005
              ? const Text('—')
              : Text(
                  formatMoney(net, currency),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: net > 0 ? AppColors.accent2 : AppColors.danger,
                  ),
                ),
        );
      },
    );
  }
}
