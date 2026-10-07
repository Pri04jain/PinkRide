import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  // Ensure Flutter bindings are initialised before any platform calls.
  // Required before calling dotenv.load() and SystemChrome methods.
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env — must happen before ApiClient reads API_BASE_URL.
  // The file is bundled as an asset in pubspec.yaml.
  await dotenv.load(fileName: '.env');

  // Lock orientation to portrait — a ride-sharing app doesn't need landscape.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Style the Android status bar to be transparent with dark icons,
  // matching our light-background design.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    // ProviderScope is the Riverpod container — must wrap the entire app.
    // All providers are initialised lazily inside this scope.
    const ProviderScope(
      child: PinkRideApp(),
    ),
  );
}

class PinkRideApp extends ConsumerWidget {
  const PinkRideApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // appRouterProvider creates the GoRouter instance wired to AuthState.
    // RouterNotifier inside it calls GoRouter.refresh() whenever auth changes,
    // which re-runs the redirect callback and sends users to the right screen.
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'PinkRide',
      debugShowCheckedModeBanner: false,

      // Apply the PinkRide brand theme globally.
      theme: AppTheme.lightTheme,

      // GoRouter takes over navigation completely.
      routerConfig: router,
    );
  }
}
