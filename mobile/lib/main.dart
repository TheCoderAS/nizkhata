import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/theme.dart';
import 'firebase_options.dart';
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

    // Long-press app icon shortcuts.
    const actions = QuickActions();
    actions.initialize((type) {
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
    actions.setShortcutItems(const [
      ShortcutItem(type: 'new_transaction', localizedTitle: 'New transaction', icon: 'ic_shortcut_add'),
      ShortcutItem(type: 'new_due', localizedTitle: 'New due', icon: 'ic_shortcut_due'),
      ShortcutItem(type: 'dues_today', localizedTitle: 'Dues today', icon: 'ic_shortcut_today'),
    ]);

    // Keep reminder schedules + the home-screen widget in sync with the data.
    _data = context.read<DataController>();
    _ws = context.read<WorkspaceController>();
    _data!.addListener(_scheduleSync);
    _scheduleSync();
  }

  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 2), () {
      final data = _data;
      if (data == null) return;
      final currency = _ws?.activeWorkspace?.baseCurrency ?? 'INR';
      DueReminders.sync(data.dues, data.settledOf);
      WidgetSync.sync(data.dues, data.settledOf, currency);
    });
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _data?.removeListener(_scheduleSync);
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
