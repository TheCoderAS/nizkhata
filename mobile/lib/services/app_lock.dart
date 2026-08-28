// App lock — biometric or device credential (PIN/pattern) gate over the whole
// app. Preference is local; authentication is Android's own. The gate locks on
// launch and whenever the app returns from background.

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLock {
  static const _prefKey = 'app_lock_enabled';
  static final _auth = LocalAuthentication();

  static Future<bool> isEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    (await SharedPreferences.getInstance()).setBool(_prefKey, value);
  }

  /// Whether this device can authenticate at all (biometrics or credentials).
  static Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock NizKhata',
        options: const AuthenticationOptions(
          biometricOnly: false, // device PIN/pattern is an acceptable fallback
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Wraps the app: shows a full-screen lock (brand mark + Unlock button) until
/// authentication succeeds; re-locks when the app goes to background. When the
/// preference is off this is a pass-through.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _enabled = false;
  bool _locked = false;
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final enabled = await AppLock.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = enabled;
    });
    if (enabled) _tryUnlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The authentication prompt itself backgrounds the app — don't re-lock
    // because of our own prompt.
    if (_authInFlight) return;
    if (state == AppLifecycleState.paused && _enabled) {
      setState(() => _locked = true);
    }
  }

  Future<void> _tryUnlock() async {
    if (_authInFlight) return;
    _authInFlight = true;
    final ok = await AppLock.authenticate();
    _authInFlight = false;
    if (mounted && ok) setState(() => _locked = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF141A2A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/splash.png', width: 120),
              const SizedBox(height: 12),
              const Text('NizKhata is locked',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _tryUnlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
