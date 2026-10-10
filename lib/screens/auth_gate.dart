import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'library_screen.dart';
import 'sign_in_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!Env.isConfigured) return const _NotConfigured();
    if (auth.currentUser == null) return const SignInScreen();
    return FutureBuilder<bool>(
      future: auth.isBandMember(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == true) return const LibraryScreen();
        return _NotAMember(email: auth.currentUser?.email ?? '');
      },
    );
  }
}

class _NotAMember extends StatelessWidget {
  const _NotAMember({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(StudioSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: StudioSpacing.lg),
              Text('呢個帳號唔係樂隊成員\n$email', textAlign: TextAlign.center),
              const SizedBox(height: StudioSpacing.lg),
              OutlinedButton(
                onPressed: context.read<AuthService>().signOut,
                child: const Text('登出'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(StudioSpacing.xl),
          child: Text(
            'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY 未設定。\n'
            '用 --dart-define 傳入（睇 README）。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
