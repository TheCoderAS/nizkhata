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
          ? FloatingActionButton.extended(
              onPressed: () => showContactForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Contact'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search contacts…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
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
                    trailing: (canManage || canViewTxns)
                        ? (c) => PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'transactions') {
                                  context.push('/txns?contact=${c.id}');
                                }
                                if (v == 'edit') showContactForm(context, existing: c);
                                if (v == 'delete') _confirmDelete(context, c);
                              },
                              itemBuilder: (_) => [
                                if (canViewTxns)
                                  const PopupMenuItem(
                                      value: 'transactions',
                                      child: Text('View transactions')),
                                if (canManage) ...const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ],
                            )
                        : null,
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
