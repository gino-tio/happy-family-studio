import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models/song.dart';
import 'screens/auth_gate.dart';
import 'screens/playlist_screen.dart';
import 'screens/song_screen.dart';
import 'services/auth_service.dart';
import 'services/library_store.dart';
import 'services/player_controller.dart';
import 'services/songs_service.dart';
import 'theme.dart';
import 'widgets/player_widgets.dart';
import 'widgets/song_cards.dart';

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

class StudioApp extends StatefulWidget {
  const StudioApp({super.key});

  @override
  State<StudioApp> createState() => _StudioAppState();
}

class _StudioAppState extends State<StudioApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _songs = SongsService();
  late final _store = LibraryStore(_songs);
  late final _player = PlayerController(_songs);

  @override
  void initState() {
    super.initState();
    // Queue entries follow renames, new covers and deletes.
    _store.addListener(() => _player.refreshFrom(_store.songs));
  }

  @override
  void dispose() {
    _store.dispose();
    _player.dispose();
    super.dispose();
  }

  void _openSong(Song song, List<Song> queue) {
    _navigator.currentState?.push(
      MaterialPageRoute(
        builder: (_) => SongScreen(songId: song.id, queue: queue),
      ),
    );
  }

  void _openPlaylist(String id) {
    _navigator.currentState?.push(
      MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider.value(value: _songs),
        ChangeNotifierProvider.value(value: _store),
        ChangeNotifierProvider.value(value: _player),
      ],
      child: MaterialApp(
        title: '開心家庭大樂隊 Studio',
        debugShowCheckedModeBanner: false,
        theme: buildStudioTheme(),
        navigatorKey: _navigator,
        // The mini player sits under every screen, outside the navigator, so
        // music keeps playing (and stays in reach) while moving around.
        builder: (context, child) => SongActions(
          openSong: _openSong,
          openPlaylist: _openPlaylist,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => ColoredBox(
                  color: StudioColors.background,
                  child: Column(
                    children: [
                      Expanded(child: child ?? const SizedBox.shrink()),
                      MiniPlayer(onOpen: (s) => _openSong(s, const [])),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
