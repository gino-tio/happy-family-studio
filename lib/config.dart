/// Build-time config — pass via `--dart-define` (never hardcode keys).
///
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// The AI music vendor key is NOT here: it lives server-side as a Supabase
/// secret read by the `studio-generate-song` Edge Function.
///
/// The backend is the shared Tio Hub Supabase project (tio-ai-hub
/// docs/SHARED_DB.md): this app's tables live in schema [dbSchema], its
/// bucket and Edge Function names start with `studio-`.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Deep link the native apps return to after Google sign-in. Must also be
  /// in Supabase Auth → URL Configuration → Redirect URLs.
  static const nativeAuthRedirect =
      'net.toolution.happyfamilystudio://login-callback';

  /// Postgres schema of this app on the shared DB (must be listed under
  /// Project Settings → Data API → Exposed schemas).
  static const dbSchema = 'app_studio';

  /// Private bucket that holds the generated audio.
  static const songsBucket = 'studio-songs';

  /// Edge Function that generates a song.
  static const generateSongFunction = 'studio-generate-song';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
