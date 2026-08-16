import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/auth_controller.dart';

/// Sign-in screen — an "aurora" brand-gradient wash behind a glowing logo,
/// feature pills, and a gradient CTA. Theme-aware, entrance-animated.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Fade + rise for a block, staggered by [delay] (0..1 of the intro).
  Widget _reveal(double delay, Widget child) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        final t = Curves.easeOutCubic
            .transform(((_intro.value - delay) / (1 - delay)).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Soft aurora blobs — the brand gradient bleeding into the surface.
          Positioned(
            top: -140,
            left: -100,
            child: _blob(280, AppColors.brand.withValues(alpha: dark ? 0.35 : 0.22)),
          ),
          Positioned(
            top: -40,
            right: -120,
            child: _blob(260, AppColors.brandTo.withValues(alpha: dark ? 0.28 : 0.18)),
          ),
          Positioned(
            bottom: -160,
            right: -80,
            child: _blob(300, AppColors.accent2.withValues(alpha: dark ? 0.12 : 0.10)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _reveal(0.0, _logoBadge(dark)),
                      const SizedBox(height: 26),
                      _reveal(
                        0.1,
                        Column(
                          children: [
                            // Brand name with a gradient sheen on the accent half.
                            ShaderMask(
                              shaderCallback: (r) => brandGradient.createShader(r),
                              child: Text(
                                'NizKhata',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8,
                                      color: Colors.white,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Every rupee, accounted for.',
                              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      _reveal(
                        0.25,
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: const [
                            _FeaturePill(icon: Icons.receipt_long_outlined, label: 'Track dues'),
                            _FeaturePill(icon: Icons.groups_outlined, label: 'Split with partners'),
                            _FeaturePill(icon: Icons.insights_outlined, label: 'Clear insights'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),
                      if (auth.error != null)
                        _reveal(
                          0.3,
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              auth.error!,
                              style: const TextStyle(color: AppColors.danger, fontSize: 13),
                            ),
                          ),
                        ),
                      _reveal(0.35, _cta(auth)),
                      const SizedBox(height: 16),
                      _reveal(
                        0.45,
                        Text(
                          'First sign-in creates your personal workspace.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 40),
                      _reveal(
                        0.55,
                        Text(
                          'nizkhata.web.app',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.6,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Logo on a soft glass tile with a brand glow behind it.
  Widget _logoBadge(bool dark) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: (dark ? Colors.white : AppColors.brand).withValues(alpha: dark ? 0.05 : 0.06),
        border: Border.all(
          color: (dark ? Colors.white : AppColors.brand).withValues(alpha: dark ? 0.10 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: dark ? 0.45 : 0.25),
            blurRadius: 60,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Image.asset('assets/icon.png'),
    );
  }

  /// Gradient "Continue with Google" call to action.
  Widget _cta(AuthController auth) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.40),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          onPressed: () => auth.signIn(),
          icon: const Icon(Icons.login, size: 20),
          label: const Text('Continue with Google'),
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.primary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, color: cs.onSurface)),
        ],
      ),
    );
  }
}
