import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';

/// Create/edit account sheet. Ports the web AccountDialog (type-conditional meta).
Future<void> showAccountForm(BuildContext context, {Account? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _AccountForm(existing: existing),
    ),
  );
}

class _AccountForm extends StatefulWidget {
  final Account? existing;
  const _AccountForm({this.existing});
  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  late String _type = widget.existing?.type ?? 'bank';
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _opening = TextEditingController(
      text: widget.existing != null ? widget.existing!.openingBalance.toString() : '0');
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late final _accountNumber = TextEditingController(text: widget.existing?.accountNumber ?? '');
  late final _cif = TextEditingController(text: widget.existing?.cif ?? '');
  late final _ifsc = TextEditingController(text: widget.existing?.ifsc ?? '');
  late final _branchName = TextEditingController(text: widget.existing?.branchName ?? '');
  late final _nameOnCard = TextEditingController(text: widget.existing?.nameOnCard ?? '');
  late final _cardLast4 = TextEditingController(text: widget.existing?.cardLast4 ?? '');
  late final _cardExpiry = TextEditingController(text: widget.existing?.cardExpiry ?? '');
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name, _opening, _code, _description, _accountNumber, _cif, _ifsc,
      _branchName, _nameOnCard, _cardLast4, _cardExpiry,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    if (ws == null || user == null) return;
    setState(() => _busy = true);
    final m = Mutations(Actor.fromUser(user));
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'type': _type,
      'openingBalance': double.tryParse(_opening.text.trim()) ?? 0,
      'code': _t(_code),
      'description': _t(_description),
      if (_type == 'bank') ...{
        'accountNumber': _t(_accountNumber),
        'cif': _t(_cif),
        'ifsc': _t(_ifsc),
        'branchName': _t(_branchName),
      },
      if (_type == 'credit_card') ...{
        'nameOnCard': _t(_nameOnCard),
        'cardLast4': _t(_cardLast4),
        'cardExpiry': _t(_cardExpiry),
      },
    };
    try {
      if (widget.existing == null) {
        await m.createAccount(ws, data);
      } else {
        await m.updateAccount(ws, widget.existing!.id, data);
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account saved')));
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'New account' : 'Edit account',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(value: 'credit_card', child: Text('Credit card')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'bank'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _opening,
                decoration: const InputDecoration(labelText: 'Opening balance'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Code / nickname (optional)'),
              ),
              if (_type == 'bank') ...[
                const SizedBox(height: 12),
                TextFormField(controller: _accountNumber, decoration: const InputDecoration(labelText: 'Account number')),
                const SizedBox(height: 12),
                TextFormField(controller: _cif, decoration: const InputDecoration(labelText: 'CIF')),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ifsc,
                  decoration: const InputDecoration(labelText: 'IFSC'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _branchName, decoration: const InputDecoration(labelText: 'Branch')),
              ],
              if (_type == 'credit_card') ...[
                const SizedBox(height: 12),
                TextFormField(controller: _nameOnCard, decoration: const InputDecoration(labelText: 'Name on card')),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cardLast4,
                  decoration: const InputDecoration(labelText: 'Card last 4'),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cardExpiry,
                  decoration: const InputDecoration(labelText: 'Expiry (MM/YY)'),
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  inputFormatters: [ExpiryTextFormatter()],
                ),
                const SizedBox(height: 8),
                Text(
                  'For your safety we never store the full card number or CVV — only the last 4 digits.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 2,
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// Normalizes free typing into MM/YY (mirrors formatExpiry in src/pages/Accounts.tsx).
class ExpiryTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.length > 4 ? digits.substring(0, 4) : digits;
    final text = trimmed.length <= 2 ? trimmed : '${trimmed.substring(0, 2)}/${trimmed.substring(2)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
