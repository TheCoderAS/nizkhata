import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'firebase_options.dart';
import 'router.dart';
import 'state/auth_controller.dart';
import 'state/data_controller.dart';
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
