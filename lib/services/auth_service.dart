import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Wraps Supabase auth + the band allowlist check.
class AuthService extends ChangeNotifier {
  AuthService() {
    _sub = _client.auth.onAuthStateChange.listen((_) {
      _memberCheck = null;
      notifyListeners();
    });
  }

  final _client = Supabase.instance.client;
  late final StreamSubscription<AuthState> _sub;
  Future<bool>? _memberCheck;

  User? get currentUser => _client.auth.currentUser;

  /// Cached per session; reset on every auth change.
  Future<bool> isBandMember() => _memberCheck ??= _client
      .rpc<bool>('is_band_member')
      .then((v) => v == true)
      .catchError((Object _) => false);

  Future<void> signInWithGoogle() => _client.auth.signInWithOAuth(
    OAuthProvider.google,
    // Web returns to the page origin; native uses the app deep link.
    redirectTo: kIsWeb ? null : Env.nativeAuthRedirect,
  );

  Future<void> signOut() => _client.auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
