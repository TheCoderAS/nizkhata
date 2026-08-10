import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

/// Open the create/edit budget sheet. Ports the web BudgetDialog fields.
Future<void> showBudgetForm(BuildContext context, {Budget? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _BudgetForm(existing: existing),
    ),
  );
}

class _BudgetForm extends StatefulWidget {
  final Budget? existing;
  const _BudgetForm({this.existing});
  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  late String? _categoryId = widget.existing?.categoryId;
  late String _period = widget.existing?.period ?? 'monthly';
  late final TextEditingController _amount =
      TextEditingController(text: widget.existing != null ? widget.existing!.amount.toString() : '0');
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) return;
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    if (ws == null || user == null) return;
    setState(() => _busy = true);
    final m = Mutations(Actor.fromUser(user));
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    try {
      if (widget.existing == null) {
        await m.createBudget(ws, {'categoryId': _categoryId, 'amount': amount, 'period': _period});
      } else {
        await m.updateBudget(ws, widget.existing!.id, {'amount': amount, 'period': _period});
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Budget saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.read<DataController>();
    final editing = widget.existing != null;
    final expenseCats = data.categories.where((c) => c.kind == 'expense').toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final budgetedIds = data.budgets.map((b) => b.categoryId).toSet();
    // When creating, only offer categories that don't already have a budget.
    final options = editing
        ? expenseCats
        : expenseCats.where((c) => !budgetedIds.contains(c.id)).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(editing ? 'Edit budget' : 'New budget',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in options) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: editing ? null : (v) => setState(() => _categoryId = v),
                validator: (v) => (v == null || v.isEmpty) ? 'Category is required' : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'monthly', label: Text('Monthly')),
                  ButtonSegment(value: 'yearly', label: Text('Yearly')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                decoration: InputDecoration(labelText: _period == 'yearly' ? 'Yearly limit' : 'Monthly limit'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
