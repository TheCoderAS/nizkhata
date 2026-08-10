import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'contact_form.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('contacts.manage');
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showContactForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Contact'),
            )
          : null,
      body: contacts.isEmpty
          ? EmptyView(
              title: 'No contacts',
              hint: 'People and businesses you transact with appear here.',
              action: canManage
                  ? FilledButton(onPressed: () => showContactForm(context), child: const Text('New contact'))
                  : null,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = contacts[i];
                final net = data.positionOf(c.id).net;
                return ListTile(
                  leading: EntityAvatar(name: c.name),
                  title: Text(c.name),
                  subtitle: Text(c.type == 'business' ? 'Business' : 'Person'),
                  onTap: canManage ? () => showContactForm(context, existing: c) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (net.abs() >= 0.005)
                        Text(
                          formatMoney(net, currency),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: net > 0 ? AppColors.accent2 : AppColors.danger,
                          ),
                        ),
                      if (canManage)
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') showContactForm(context, existing: c);
                            if (v == 'delete') _confirmDelete(context, c);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, Contact c) {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: const Text('This removes the contact. Linked transactions are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              if (ws == null || user == null) return;
              try {
                await Mutations(Actor.fromUser(user)).deleteContact(ws, c.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Contact deleted')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
