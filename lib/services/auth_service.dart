import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Wraps Supabase auth + the band membership check (core.app_members on the
/// shared DB, read through `app_studio.me()`).
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
  /// `app_studio.me()` returns the caller's role in the app, or null.
  Future<bool> isBandMember() => _memberCheck ??= _client
      .schema(Env.dbSchema)
      .rpc<dynamic>('me')
      .then((role) => role != null)
      .catchError((Object _) => false);

  Future<void> signInWithGoogle() => _client.auth.signInWithOAuth(
    OAuthProvider.google,
    // Web returns to the page origin; native uses the app deep link. Always
    // pass it: the shared project's Site URL belongs to another app.
    redirectTo: kIsWeb ? Uri.base.origin : Env.nativeAuthRedirect,
  );

  Future<void> signOut() => _client.auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
