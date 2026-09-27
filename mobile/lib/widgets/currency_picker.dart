// Choosing the currency a workspace keeps its books in.
//
// The choice is made once, when the workspace is created, and can never be
// changed, so everything here leans towards the person seeing plainly what
// they are picking: the full name and the symbol beside the code, a search
// that understands "dollar" as well as "AED", and a note that says the choice
// is for good.

import 'package:flutter/material.dart';

import '../core/currency.dart';
import 'common.dart';

/// The currency to preselect for a new person, from their phone's region.
///
/// Only a starting point for a choice they confirm. A phone that says nothing
/// useful (no region, or one we have no currency for) falls back to the rupee,
/// since that is who the app has mostly served.
String suggestedCurrency(Locale? locale) => currencyForCountry(locale?.countryCode) ?? 'INR';

/// The currencies matching [query], in catalogue order. Matches the code
/// ("aed"), any word of the name ("dollar", "rupee") and the symbol ("£").
List<CurrencySpec> filterCurrencies(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kCurrencies;
  return [
    for (final c in kCurrencies)
      if (c.code.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q) ||
          c.symbol.trim().toLowerCase().contains(q))
        c,
  ];
}

/// Open the searchable currency list. Resolves to the chosen code, or null if
/// the sheet was dismissed.
Future<String?> showCurrencyPicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: CurrencyPickerSheet(selected: selected),
    ),
  );
}

class CurrencyPickerSheet extends StatefulWidget {
  final String? selected;
  const CurrencyPickerSheet({super.key, this.selected});

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matches = filterCurrencies(_query);
    // A fixed share of the screen, so the sheet does not jump in height as the
    // list shrinks under a search.
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose currency', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SearchField(hint: 'Search by name or code', onChanged: (v) => setState(() => _query = v)),
              ],
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No currency matches "${_query.trim()}".',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: matches.length,
                    itemBuilder: (_, i) {
                      final c = matches[i];
                      final selected = c.code == widget.selected;
                      return ListTile(
                        key: ValueKey('currency-${c.code}'),
                        leading: CurrencySymbolBadge(c),
                        title: Text(c.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(c.code),
                        selected: selected,
                        trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
                        onTap: () => Navigator.of(context).pop(c.code),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The currency's symbol on a soft tile, the way the app marks an entity.
class CurrencySymbolBadge extends StatelessWidget {
  final CurrencySpec spec;
  const CurrencySymbolBadge(this.spec, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      // Symbols run from "₹" to "KSh"; scale the long ones down rather than
      // let them spill out of the tile.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          spec.symbol.trim(),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.primary),
        ),
      ),
    );
  }
}

/// The chosen currency as a form field: tap to change it through the picker.
class CurrencyField extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;
  const CurrencyField({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = currencySpec(value);
    final enabled = onChanged != null;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: !enabled
            ? null
            : () async {
                final code = await showCurrencyPicker(context, selected: value);
                if (code != null) onChanged!(code);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              CurrencySymbolBadge(spec),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spec.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(spec.code, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 8),
                Icon(Icons.expand_more, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Says, once and plainly, that the currency is for good.
class CurrencyLockNote extends StatelessWidget {
  const CurrencyLockNote({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "The workspace keeps all its figures in this currency. It can't be changed later.",
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
