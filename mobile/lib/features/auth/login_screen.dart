import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/animated_button.dart';
import '../../core/widgets/glass_container.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await ref.read(authRepositoryProvider).login(_userCtrl.text, _passCtrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ref.invalidate(sessionFutureProvider);
    await ref.read(sessionFutureProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/bibliainteligente.png',
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0A1628), Color(0xFF0D0D0D)],
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottomInset),
                child: GlassContainer(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  blurSigma: 8,
                  gradientStartAlpha: 0.05,
                  gradientEndAlpha: 0.02,
                  borderColor: Colors.white.withValues(alpha: 0.28),
                  overlayColor: Colors.black.withValues(alpha: 0.16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'FAÇA LOGIN',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 2)),
                                Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1)),
                              ],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Acesse sua jornada espiritual',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.onBackgroundMuted,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1)),
                              ],
                            ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _userCtrl,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        style: const TextStyle(color: AppColors.onBackground),
                        decoration: InputDecoration(
                          labelText: 'Usuário ou e-mail',
                          labelStyle: const TextStyle(color: AppColors.onBackgroundMuted),
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                          filled: true,
                          fillColor: AppColors.surface.withValues(alpha: 0.9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(color: AppColors.onBackground),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          labelStyle: const TextStyle(color: AppColors.onBackgroundMuted),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: AppColors.onBackgroundMuted,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          filled: true,
                          fillColor: AppColors.surface.withValues(alpha: 0.9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      AnimatedButton(
                        onPressed: _busy ? null : _submit,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('ENTRAR', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Ainda não tem uma conta?',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.onBackgroundMuted,
                                  shadows: const [
                                    Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                                  ],
                                ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Clique aqui e crie seu cadastro',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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
}
