import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(StudioSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.graphic_eq,
                    size: 64,
                    color: StudioColors.neon,
                  ),
                  const SizedBox(height: StudioSpacing.lg),
                  Text('開心家庭大樂隊', style: text.headlineMedium),
                  Text(
                    'Happy Family Studio',
                    style: text.titleMedium?.copyWith(
                      color: StudioColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: StudioSpacing.xxl),
                  FilledButton.icon(
                    onPressed: () =>
                        context.read<AuthService>().signInWithGoogle(),
                    icon: const Icon(Icons.login),
                    label: const Text('用 Google 登入'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
