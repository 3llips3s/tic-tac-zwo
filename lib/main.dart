import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tic_tac_zwo/app.dart';
import 'package:tic_tac_zwo/config/app_config/app_config.dart';
import 'package:tic_tac_zwo/config/game_config/constants.dart';
import 'package:tic_tac_zwo/features/wortschatz/data/models/saved_noun_hive.dart';
import 'package:tic_tac_zwo/hive/hive_registrar.g.dart';
import 'package:wiredash/wiredash.dart';

import 'config/game_config/theme.dart';
import 'features/game/online/data/models/german_noun_hive.dart';
import 'features/navigation/routes/app_router.dart';
import 'features/navigation/routes/route_names.dart';
import 'features/settings/logic/audio_manager.dart';
import 'features/settings/logic/audio_settings_listener.dart';
import 'features/settings/logic/haptics_manager.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    await dotenv.load(fileName: '.env');

    if (!AppConfig.isConfigValid) {
      throw Exception('Missing required environment variables');
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );

    if (kIsWeb) {
      Hive.init(null);
    } else {
      final Directory appDocumentDir = await getApplicationDocumentsDirectory();
      Hive.init(appDocumentDir.path);
    }

    Hive.registerAdapters();

    await Hive.openBox<GermanNounHive>('german_nouns');
    await Hive.openBox<SavedNounHive>('saved_nouns');
    await Hive.openBox<String>('seen_nouns');
    await Hive.openBox('sync_info');
    await Hive.openBox('user_preferences');
    await Hive.openBox('wordle_coins');

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark));

    runApp(const ProviderScope(child: MainApp()));
  } catch (e) {
    developer.log('FATAL: App failed to initialize.', name: 'main');
    developer.log('Error: $e', name: 'main');
    runApp(InitializationErrorApp(error: e));
  }
}

class MainApp extends ConsumerStatefulWidget {
  // global key for scaffold messenger
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // init audio and haptics
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AudioManager.instance.initialize(ref).then((_) {
        if (!kIsWeb) {
          AudioManager.instance.playBackgroundMusic(fade: true);
        }
      });
      HapticsManager.initialize(ref);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      AudioManager.instance.pauseBackgroundMusic(fade: true, userPaused: false);
    } else if (state == AppLifecycleState.resumed) {
      if (AudioManager.instance.musicShouldBePlaying) {
        AudioManager.instance.playBackgroundMusic(fade: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AudioSettingsListener(
      child: Wiredash(
        projectId: AppConfig.wiredashProjectId,
        secret: AppConfig.wiredashSecret,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          onGenerateRoute: AppRouter.generateRoute,
          initialRoute: RouteNames.home,
          scaffoldMessengerKey: MainApp.scaffoldMessengerKey,
          home: DataInitializationWrapper(
            child: const App(),
          ),
        ),
      ),
    );
  }
}

class InitializationErrorApp extends StatelessWidget {
  final Object error;
  const InitializationErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: colorGrey300,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Fehler. Bitter erneut versuchen. $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
