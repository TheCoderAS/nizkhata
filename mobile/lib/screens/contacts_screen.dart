import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/entity_card_list.dart';
import '../widgets/row_actions.dart';
import '../widgets/undo_delete.dart';
import 'contact_form.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('contacts.manage');
    final canViewTxns = ws.can('transactions.view');
    final query = _search.trim().toLowerCase();
    final contacts = data.contacts
        .where((c) => c.connectionUid == null && c.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      floatingActionButton: canManage
          ? AppFab(
              onPressed: () => showContactForm(context),
              tooltip: 'Add contact',
              icon: Icons.add,
            )
          : null,
      body: Column(
        children: [
          Padding(
            // Same inset as every other list screen's search row.
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              controller: _searchController,
              hint: 'Search contacts…',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? EmptyView(
                    icon: query.isNotEmpty ? Icons.search_off : Icons.people_outline,
                    title: query.isNotEmpty ? 'No matches' : 'No contacts',
                    hint: query.isNotEmpty
                        ? null
                        : 'People and businesses you transact with appear here.',
                    action: canManage && query.isEmpty
                        ? FilledButton(
                            onPressed: () => showContactForm(context),
                            child: const Text('New contact'),
                          )
                        : null,
                  )
                : EntityCardList<Contact>(
                    listId: 'contacts',
                    rows: contacts,
                    onRowTap: (c) => context.push('/contacts/${c.id}'),
                    leading: (c) => EntityAvatar(name: c.name),
                    // Swipe right for the contact's transactions; long-press
                    // for the full action sheet (was the 3-dot menu).
                    wrapCard: (c, card) {
                      final txns = canViewTxns
                          ? RowAction(
                              icon: Icons.receipt_long_outlined,
                              label: 'View transactions',
                              onTap: () => context.push('/txns?contact=${c.id}'))
                          : null;
                      return RowActions(
                        id: c.id,
                        title: c.name,
                        swipeStart: txns,
                        menu: [
                          if (txns != null) txns,
                          if (canManage)
                            RowAction(
                                icon: Icons.edit_outlined,
                                label: 'Edit',
                                onTap: () => showContactForm(context, existing: c)),
                          if (canManage)
                            RowAction(
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                destructive: true,
                                onTap: () => _confirmDelete(context, c)),
                        ],
                        child: card,
                      );
                    },
                    fields: [
                      CardField<Contact>(
                        key: 'name',
                        label: 'Name',
                        role: CardRole.title,
                        locked: true,
                        sortValue: (c) => c.name.toLowerCase(),
                        widget: (c) => Row(
                          children: [
                            Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                            if (c.relationship == 'family') ...[
                              const SizedBox(width: 8),
                              _FamilyBadge(),
                            ],
                          ],
                        ),
                      ),
                      CardField<Contact>(
                        key: 'type',
                        label: 'Type',
                        icon: Icons.label_outline,
                        sortValue: (c) => c.type,
                        text: (c) => c.type == 'business' ? 'Business' : 'Person',
                      ),
                      CardField<Contact>(
                        key: 'net',
                        label: 'Net position',
                        role: CardRole.amount,
                        sortValue: (c) => data.positionOf(c.id).net,
                        widget: (c) {
                          final net = data.positionOf(c.id).net;
                          if (net.abs() < 0.005) return const Text('—');
                          return Text(
                            formatMoney(net, currency),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: net > 0 ? AppColors.accent2 : AppColors.danger,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Contact c) {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
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
                await deleteWithUndo(context,
                    actor: Actor.fromUser(user),
                    collection: 'contacts',
                    workspaceId: ws,
                    id: c.id,
                    label: 'Contact');
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

class _FamilyBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        'Family',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      ),
    );
  }
}
