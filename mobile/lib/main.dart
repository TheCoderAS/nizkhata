import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/format.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'data/models.dart';
import 'data/mutations.dart';
import 'router.dart';
import 'services/app_lock.dart';
import 'services/due_reminders.dart';
import 'services/pdf_brand.dart';
import 'services/min_version.dart';
import 'services/push_registration.dart';
import 'services/widget_sync.dart';
import 'state/auth_controller.dart';
import 'state/data_controller.dart';
import 'state/shared_controller.dart';
import 'state/theme_controller.dart';
import 'state/workspace_controller.dart';
import 'core/ws_time.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Dates follow the phone. All locales' date symbols ship with the app, so
  // this needs no network; resolveDateLocale keeps it to an English variant,
  // since the rest of the app is written in English.
  await initializeDateFormatting();
  AppLocale.date = resolveDateLocale(PlatformDispatcher.instance.locale);
  Intl.defaultLocale = AppLocale.date;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // The PDF font, read ahead so the first shared PDF already has it. The
  // screens that build PDFs await it too; this only saves them the wait.
  unawaited(PdfTypeface.load());
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              c.setUid(auth.user?.uid);
              // Where to send this person's notifications, once sign-in has
              // loaded (before then "nobody" only means "not known yet").
              if (!auth.loading) PushRegistration.sync(auth.user?.uid);
            });
            return c;
          },
        ),
        ChangeNotifierProxyProvider<WorkspaceController, DataController>(
          create: (_) => DataController(),
          update: (_, ws, data) {
            final c = data ?? DataController();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => c.setWorkspace(ws.activeWorkspaceId,
                    scope: ws.dataScope, timeZone: ws.activeWorkspace?.timeZone));
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

class _RootState extends State<_Root> with WidgetsBindingObserver {
  late final router = buildRouter(context.read<AuthController>());
  Timer? _syncDebounce;
  DataController? _data;
  WorkspaceController? _ws;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A build the books have moved past is asked to update before use.
    updateRequired().then((v) {
      if (v && mounted) setState(() => _mustUpdate = true);
    });
    // Notification taps route into the app (works warm and, via the pending
    // route, cold-started from a tap).
    DueReminders.onOpenRoute = _openNotification;
    DueReminders.init().then((_) {
      final pending = DueReminders.takePendingRoute();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openNotification(pending));
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
          final now = WsTime.now();
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

  /// Open a notification's route. A reminder names its workspace (`ws=`):
  /// switch to it first, if this person is still a member, so the day shown
  /// is that workspace's dues and not whichever one happened to be open.
  Future<void> _openNotification(String route) async {
    final uri = Uri.tryParse(route);
    if (uri == null) return;
    final wsId = uri.queryParameters['ws'];
    final ws = _ws ?? context.read<WorkspaceController>();
    if (wsId != null && wsId != ws.activeWorkspaceId && ws.memberships.any((m) => m.workspaceId == wsId)) {
      await ws.switchWorkspace(wsId);
    }
    final rest = Map<String, String>.from(uri.queryParameters)..remove('ws');
    router.push(uri.replace(queryParameters: rest.isEmpty ? null : rest).toString());
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
        const ShortcutItem(
            type: 'new_transaction', localizedTitle: 'New transaction', icon: 'ic_shortcut_add'),
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
    _syncDebounce = Timer(const Duration(seconds: 2), _runSync);
  }

  void _runSync() {
    _syncDebounce?.cancel();
    final data = _data;
    if (data == null) return;
    final currency = _ws?.currency ?? 'INR';
    // Reminders, repeating dues and card bills are the backend's job now; the
    // phone only keeps its own widget and shortcuts in step.
    WidgetSync.sync(data.dues, data.settledOf, currency);
    _updateShortcuts();
    _attemptAutoLink();
  }

  /// Flush a pending sync before going away, so the widget shows the latest.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_syncDebounce?.isActive ?? false) _runSync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncDebounce?.cancel();
    _data?.removeListener(_scheduleSync);
    _ws?.removeListener(_scheduleSync);
    super.dispose();
  }

  bool _mustUpdate = false;

  @override
  Widget build(BuildContext context) {
    if (_mustUpdate) {
      return MaterialApp(
        title: 'Niz Khata',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: context.watch<ThemeController>().mode,
        home: const UpdateRequiredScreen(),
      );
    }
    return LockGate(
      child: MaterialApp.router(
        title: 'Niz Khata',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: context.watch<ThemeController>().mode,
        routerConfig: router,
      ),
    );
  }
}
