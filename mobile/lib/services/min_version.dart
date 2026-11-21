// "This version is too old": a version that would write dates the old way
// (or otherwise disagree with the books) can be asked to update before it is
// used. The minimum is the document config/app, field minVersionCode, set by
// hand in the Firebase console when a release must be required. No document,
// or no field, asks nothing.
//
// The version code is the build's own (--dart-define=APP_VERSION_CODE, set by
// the release workflow from the tag). A development build has none and is
// never blocked.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const int kAppVersionCode = int.fromEnvironment('APP_VERSION_CODE');
const String kPlayListing = 'https://play.google.com/store/apps/details?id=com.nizkhata.nizkhata';

/// True when the books ask for a newer version than this one.
Future<bool> updateRequired() async {
  if (kAppVersionCode <= 0) return false;
  try {
    final snap = await FirebaseFirestore.instance.collection('config').doc('app').get();
    final min = (snap.data()?['minVersionCode'] as num?)?.toInt() ?? 0;
    return kAppVersionCode < min;
  } catch (_) {
    return false; // offline or no document: never lock anyone out
  }
}

/// Shown over everything until the person updates.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update, size: 56, color: cs.primary),
                const SizedBox(height: 16),
                Text('Update Niz Khata', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'This version is too old to keep your books in step. Update from Google Play to carry on; nothing in your books is lost.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(kPlayListing), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Google Play'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
