// First sign-in: choose the currency before the workspace exists.
//
// A workspace's currency can never be changed, so it is not guessed on the
// person's behalf. The phone's region only preselects one; nothing is created
// until they confirm it. The router keeps a signed-in person with no
// workspace on this screen, and moves them on to the dashboard as soon as the
// workspace is made.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/auth_controller.dart';
import '../widgets/common.dart';
import '../widgets/currency_picker.dart';

class ChooseCurrencyScreen extends StatelessWidget {
  const ChooseCurrencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return ChooseCurrencyView(
      firstName: (auth.user?.displayName ?? '').trim().split(' ').first,
      initialCurrency: suggestedCurrency(WidgetsBinding.instance.platformDispatcher.locale),
      onConfirm: auth.createFirstWorkspace,
      onSignOut: auth.signOut,
    );
  }
}

/// The screen itself, free of Firebase so it can be tested.
class ChooseCurrencyView extends StatefulWidget {
  final String firstName;
  final String initialCurrency;

  /// Creates the workspace. The router takes over once it succeeds; a throw is
  /// shown here and the person can try again.
  final Future<void> Function(String currency) onConfirm;
  final Future<void> Function() onSignOut;

  const ChooseCurrencyView({
    super.key,
    required this.firstName,
    required this.initialCurrency,
    required this.onConfirm,
    required this.onSignOut,
  });

  @override
  State<ChooseCurrencyView> createState() => _ChooseCurrencyViewState();
}

class _ChooseCurrencyViewState extends State<ChooseCurrencyView> {
  late String _currency = widget.initialCurrency;
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_currency);
      // Leave _busy set: the router is about to replace this screen, and a
      // re-enabled button in the meantime would invite a second workspace.
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't set up your workspace. Check your connection and try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final greeting = widget.firstName.isEmpty ? 'Welcome to NizKhata' : 'Welcome, ${widget.firstName}';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: brandGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 20),
                  Text(greeting, style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'One quick choice and your workspace is ready. Which currency do you keep your money in?',
                    style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('Currency'),
                  CurrencyField(
                    value: _currency,
                    onChanged: _busy ? null : (c) => setState(() => _currency = c),
                  ),
                  const SizedBox(height: 12),
                  const CurrencyLockNote(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _confirm,
                      child: _busy
                          ? const SizedBox(
                              height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Create my workspace'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : widget.onSignOut,
                      child: const Text('Use a different account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
