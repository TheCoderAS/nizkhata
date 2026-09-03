import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/discard_guard.dart';
import '../widgets/common.dart';
import '../widgets/txn_lines_editor.dart' show amountText;

/// Create/edit account sheet. Ports the web AccountDialog (type-conditional meta).
Future<void> showAccountForm(BuildContext context, {Account? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // Guarded form: a swipe-down would pop the route without asking, so
    // dragging is off and DiscardGuard supplies the close button.
    showDragHandle: false,
    enableDrag: false,
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

/// Hides the "0/2" character counter under a two-digit day field, which is
/// noise beside a helper line that already says what to type.
Widget? _noCounter(BuildContext _,
        {required int currentLength, required bool isFocused, required int? maxLength}) =>
    null;

class _AccountFormState extends State<_AccountForm> {
  @override
  void initState() {
    super.initState();
    _fp0 = _fp();
  }

  // Unsaved-edit detection: snapshot on open, compare on close.
  late final String _fp0;
  String _fp() => [
        _type,
        _name.text,
        _opening.text,
        _code.text,
        _description.text,
        _accountNumber.text,
        _cif.text,
        _ifsc.text,
        _branchName.text,
        _nameOnCard.text,
        _cardLast4.text,
        _cardExpiry.text,
        _statementDay.text,
        _paymentDueDay.text,
        _creditLimit.text
      ].join('|');

  /// A cycle day only counts when its partner is set too: one day of the pair
  /// on its own cannot place a statement, and a half-configured card would
  /// raise no bill while looking configured.
  int? _cycleDay(TextEditingController c) {
    final day = int.tryParse(c.text.trim());
    if (day == null || day < 1 || day > 31) return null;
    final other = identical(_statementDay, c) ? _paymentDueDay : _statementDay;
    final otherDay = int.tryParse(other.text.trim());
    if (otherDay == null || otherDay < 1 || otherDay > 31) return null;
    return day;
  }

  String? _validateDay(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final day = int.tryParse(text);
    if (day == null || day < 1 || day > 31) return 'Use a day from 1 to 31';
    return null;
  }

  final _formKey = GlobalKey<FormState>();
  late String _type = widget.existing?.type ?? 'bank';
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _opening =
      TextEditingController(text: widget.existing != null ? widget.existing!.openingBalance.toString() : '0');
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late final _accountNumber = TextEditingController(text: widget.existing?.accountNumber ?? '');
  late final _cif = TextEditingController(text: widget.existing?.cif ?? '');
  late final _ifsc = TextEditingController(text: widget.existing?.ifsc ?? '');
  late final _branchName = TextEditingController(text: widget.existing?.branchName ?? '');
  late final _nameOnCard = TextEditingController(text: widget.existing?.nameOnCard ?? '');
  late final _cardLast4 = TextEditingController(text: widget.existing?.cardLast4 ?? '');
  late final _cardExpiry = TextEditingController(text: widget.existing?.cardExpiry ?? '');
  late final _statementDay = TextEditingController(text: widget.existing?.statementDay?.toString() ?? '');
  late final _paymentDueDay = TextEditingController(text: widget.existing?.paymentDueDay?.toString() ?? '');
  late final _creditLimit = TextEditingController(text: amountText(widget.existing?.creditLimit ?? 0));
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _opening,
      _code,
      _description,
      _accountNumber,
      _cif,
      _ifsc,
      _branchName,
      _nameOnCard,
      _cardLast4,
      _cardExpiry,
      _statementDay,
      _paymentDueDay,
      _creditLimit,
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
        // The billing cycle. Both days are needed before a statement means
        // anything, so a half-filled pair stores neither.
        'statementDay': _cycleDay(_statementDay),
        'paymentDueDay': _cycleDay(_paymentDueDay),
        'creditLimit': double.tryParse(_creditLimit.text.trim()),
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
    return DiscardGuard(
      title: widget.existing == null ? 'New account' : 'Edit account',
      isDirty: () => _fp() != _fp0,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: kSheetFieldTopPad),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel('Account'),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 14),
              TextFormField(
                controller: _opening,
                decoration: const InputDecoration(labelText: 'Opening balance'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Code / nickname (optional)'),
              ),
              if (_type == 'bank') ...[
                const SizedBox(height: 22),
                SectionLabel('Bank details'),
                TextFormField(
                    controller: _accountNumber,
                    decoration: const InputDecoration(labelText: 'Account number')),
                const SizedBox(height: 14),
                TextFormField(controller: _cif, decoration: const InputDecoration(labelText: 'CIF')),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _ifsc,
                  decoration: const InputDecoration(labelText: 'IFSC'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                ),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _branchName, decoration: const InputDecoration(labelText: 'Branch')),
              ],
              if (_type == 'credit_card') ...[
                const SizedBox(height: 22),
                SectionLabel('Card details'),
                TextFormField(
                    controller: _nameOnCard, decoration: const InputDecoration(labelText: 'Name on card')),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cardLast4,
                  decoration: const InputDecoration(labelText: 'Card last 4'),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cardExpiry,
                  decoration: const InputDecoration(labelText: 'Expiry (MM/YY)'),
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  inputFormatters: [ExpiryTextFormatter()],
                ),
                const SizedBox(height: 22),
                SectionLabel('Billing cycle'),
                Text(
                  'Both days are on your statement. Fill them in and NizKhata raises the '
                  'bill for you each month, for what the card owed on the statement day.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _statementDay,
                        decoration: const InputDecoration(
                          labelText: 'Statement day',
                          helperText: 'Day of month',
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 2,
                        buildCounter: _noCounter,
                        validator: _validateDay,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _paymentDueDay,
                        decoration: const InputDecoration(
                          labelText: 'Payment due day',
                          helperText: 'Day of month',
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 2,
                        buildCounter: _noCounter,
                        validator: _validateDay,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _creditLimit,
                  decoration: const InputDecoration(
                    labelText: 'Credit limit (optional)',
                    prefixText: '₹ ',
                    helperText: 'Shows how much of the card you have used',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                Text(
                  'For your safety we never store the full card number or CVV — only the last 4 digits.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SectionLabel('Notes'),
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
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
