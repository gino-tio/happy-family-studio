import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/songs_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web uses the implicit OAuth flow, not PKCE: Safari ITP and some mobile
  // browsers wipe the PKCE code verifier from localStorage during the
  // Google redirect bounce (tio-help pitfall #3).
  await Supabase.initialize(
    url: Env.isConfigured ? Env.supabaseUrl : 'https://preview.supabase.co',
    publishableKey: Env.isConfigured ? Env.supabasePublishableKey : 'preview',
    authOptions: FlutterAuthClientOptions(
      authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
    ),
  );

  runApp(const StudioApp());
}

class StudioApp extends StatelessWidget {
  const StudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => SongsService()),
      ],
      child: MaterialApp(
        title: '開心家庭大樂隊 Studio',
        debugShowCheckedModeBanner: false,
        theme: buildStudioTheme(),
        home: const AuthGate(),
      ),
    );
  }
}
