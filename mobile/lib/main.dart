import 'dart:async';


import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/theme.dart';
import 'firebase_options.dart';
import 'data/models.dart';
import 'data/mutations.dart';
import 'router.dart';
import 'services/due_reminders.dart';
import 'services/widget_sync.dart';
import 'state/auth_controller.dart';
import 'state/data_controller.dart';
import 'state/shared_controller.dart';
import 'state/theme_controller.dart';
import 'state/workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'en_IN';
  await initializeDateFormatting('en_IN', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const NizkhataApp());
}

class NizkhataApp extends StatelessWidget {
  const NizkhataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProxyProvider<AuthController, WorkspaceController>(
          create: (_) => WorkspaceController(),
          update: (_, auth, ws) {
            final c = ws ?? WorkspaceController();
            WidgetsBinding.instance.addPostFrameCallback((_) => c.setUid(auth.user?.uid));
            return c;
          },
        ),
        ChangeNotifierProxyProvider<WorkspaceController, DataController>(
          create: (_) => DataController(),
          update: (_, ws, data) {
            final c = data ?? DataController();
            WidgetsBinding.instance.addPostFrameCallback((_) => c.setWorkspace(ws.activeWorkspaceId));
            return c;
          },
        ),
        ChangeNotifierProxyProvider<AuthController, SharedController>(
          create: (_) => SharedController(),
          update: (_, auth, shared) {
            final c = shared ?? SharedController();
            WidgetsBinding.instance.addPostFrameCallback((_) => c.setUid(auth.user?.uid));
            return c;
          },
        ),
      ],
      child: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late final router = buildRouter(context.read<AuthController>());
  Timer? _syncDebounce;
  DataController? _data;
  WorkspaceController? _ws;

  @override
  void initState() {
    super.initState();
    // Notification taps route into the app (works warm and, via the pending
    // route, cold-started from a tap).
    DueReminders.onOpenRoute = (route) => router.push(route);
    DueReminders.init().then((_) {
      final pending = DueReminders.takePendingRoute();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => router.push(pending));
      }
    });

    // Long-press app icon shortcuts (the list itself is role-aware and built
    // in _updateShortcuts once permissions are known).
    _quickActions.initialize((type) {
      switch (type) {
        case 'new_transaction':
          router.push('/txns?add=1');
          break;
        case 'new_due':
          router.push('/dues-day?add=1');
          break;
        case 'dues_today':
          final now = DateTime.now();
          final d =
              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          router.push('/dues-day?date=$d');
          break;
      }
    });

    // Keep reminder schedules, the home-screen widget, the role-aware
    // shortcuts and the contact auto-link in sync with the data.
    _data = context.read<DataController>();
    _ws = context.read<WorkspaceController>();
    _data!.addListener(_scheduleSync);
    _ws!.addListener(_scheduleSync);
    _scheduleSync();
  }

  static const _quickActions = QuickActions();
  String _shortcutSignature = '';

  /// Only offer shortcuts the user's role actually permits — a viewer should
  /// never see "New transaction" on the long-press menu.
  void _updateShortcuts() {
    final ws = _ws;
    if (ws == null || ws.activeWorkspaceId == null) return;
    final items = <ShortcutItem>[
      if (ws.can('transactions.create'))
        const ShortcutItem(type: 'new_transaction', localizedTitle: 'New transaction', icon: 'ic_shortcut_add'),
      if (ws.can('dues.manage'))
        const ShortcutItem(type: 'new_due', localizedTitle: 'New due', icon: 'ic_shortcut_due'),
      if (ws.can('dues.view'))
        const ShortcutItem(type: 'dues_today', localizedTitle: 'Dues today', icon: 'ic_shortcut_today'),
    ];
    final sig = items.map((i) => i.type).join(',');
    if (sig == _shortcutSignature) return;
    _shortcutSignature = sig;
    if (items.isEmpty) {
      _quickActions.clearShortcutItems();
    } else {
      _quickActions.setShortcutItems(items);
    }
  }

  /// Auto-link this member to the workspace contact with their sign-in email
  /// (once, when no link exists). Admins can override on the Members screen.
  Future<void> _attemptAutoLink() async {
    final ws = _ws;
    final data = _data;
    final auth = context.read<AuthController>();
    final user = auth.user;
    if (ws == null || data == null || user == null) return;
    final email = user.email?.toLowerCase().trim();
    if (email == null || email.isEmpty) return;
    Membership? mine;
    for (final m in ws.workspaceMembers) {
      if (m.uid == user.uid) {
        mine = m;
        break;
      }
    }
    if (mine == null || mine.linkedContactId != null) return;
    for (final c in data.contacts) {
      final emails = [
        for (final e in c.emails) e.value.toLowerCase().trim(),
        if (c.email != null) c.email!.toLowerCase().trim(),
      ];
      if (emails.contains(email)) {
        try {
          await Mutations(Actor.fromUser(user)).setMembershipContactLink(mine.id, c.id);
        } catch (e) {
          debugPrint('auto-link failed: $e');
        }
        return;
      }
    }
  }

  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 2), () {
      final data = _data;
      if (data == null) return;
      final currency = _ws?.activeWorkspace?.baseCurrency ?? 'INR';
      DueReminders.sync(data.dues, data.settledOf);
      WidgetSync.sync(data.dues, data.settledOf, currency);
      _updateShortcuts();
      _attemptAutoLink();
    });
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _data?.removeListener(_scheduleSync);
    _ws?.removeListener(_scheduleSync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NizKhata',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: context.watch<ThemeController>().mode,
      routerConfig: router,
    );
  }
}
