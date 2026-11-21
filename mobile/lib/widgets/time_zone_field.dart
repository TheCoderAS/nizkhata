// The workspace's time zone as a form field, with a searchable picker. Shown
// where a workspace is made; fixed from then on, like its currency.

import 'package:flutter/material.dart';

import '../core/ws_time.dart';

/// "Asia/Kolkata" as people read it: "Kolkata".
String zoneCity(String zone) => zone.split('/').last.replaceAll('_', ' ');

/// "Kolkata, Asia · UTC+5:30".
String zoneLabel(String zone) {
  final parts = zone.split('/');
  final city = zoneCity(zone);
  final region = parts.length > 1 ? parts.first.replaceAll('_', ' ') : '';
  final offset = WsTime.offsetLabel(zone);
  return [if (region.isNotEmpty) '$city, $region' else city, if (offset.isNotEmpty) offset].join(' · ');
}

class TimeZoneField extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;
  const TimeZoneField({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('time-zone-field'),
        borderRadius: BorderRadius.circular(14),
        onTap: !enabled
            ? null
            : () async {
                final z = await showDialog<String>(
                  context: context,
                  useRootNavigator: true,
                  builder: (_) => _TimeZonePicker(selected: value),
                );
                if (z != null) onChanged!(z);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.schedule, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(zoneLabel(value),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (enabled) Icon(Icons.expand_more, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeZonePicker extends StatefulWidget {
  final String selected;
  const _TimeZonePicker({required this.selected});
  @override
  State<_TimeZonePicker> createState() => _TimeZonePickerState();
}

class _TimeZonePickerState extends State<_TimeZonePicker> {
  final _query = TextEditingController();
  late final List<String> _all = WsTime.allZones();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final shown = q.isEmpty ? _all : _all.where((z) => z.toLowerCase().replaceAll('_', ' ').contains(q)).toList();
    return AlertDialog(
      title: const Text('Time zone'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'City, e.g. Kolkata or Bangkok'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final z = shown[i];
                  return ListTile(
                    dense: true,
                    title: Text(zoneLabel(z)),
                    trailing: z == widget.selected ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, z),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// Says, once and plainly, that the time zone is for good.
class TimeZoneLockNote extends StatelessWidget {
  const TimeZoneLockNote({super.key});

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
            "Its days start and end here, wherever your phone is. It can't be changed later.",
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
