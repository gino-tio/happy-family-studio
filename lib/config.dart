/// Build-time config — pass via `--dart-define` (never hardcode keys).
///
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// The AI music vendor key is NOT here: it lives server-side as a Supabase
/// secret read by the `generate-song` Edge Function.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Deep link the native apps return to after Google sign-in. Must also be
  /// in Supabase Auth → URL Configuration → Redirect URLs.
  static const nativeAuthRedirect =
      'net.toolution.happyfamilystudio://login-callback';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
