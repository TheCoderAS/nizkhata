// What this phone keeps for the signed-in person, outside Firestore: the
// statement passwords it remembers, scheduled reminders, the home-screen
// widget's figures, and preferences. Cleared when the account is deleted, so
// nothing of it outlives the account on the device.

import 'package:shared_preferences/shared_preferences.dart';

import 'due_reminders.dart';
import 'password_store.dart';
import 'widget_sync.dart';

Future<void> clearLocalData() async {
  await PasswordStore.instance.clearAll();
  await DueReminders.sync(const [], (_) => 0); // cancels every scheduled reminder
  await WidgetSync.sync(const [], (_) => 0, 'INR'); // empties the widget
  try {
    await (await SharedPreferences.getInstance()).clear();
  } catch (_) {}
}
