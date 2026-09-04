import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// PinkRide app entry point.
///
/// Boot sequence:
///   1. Lock orientation to portrait (ride apps don't need landscape)
///   2. Load .env (API URL, Razorpay key, Maps key)
///   3. Wrap in ProviderScope — required by Riverpod
///   4. AppRouter's redirect reads AuthState and sends the user
///      to the right screen (splash → phone input OR home screen)
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only — most ride-hailing apps lock this
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables from assets/.env
  await dotenv.load(fileName: '.env');

  runApp(
    // ProviderScope is Riverpod's root widget.
    // Every Provider in the app is scoped to this — they're created lazily
    // and disposed when no longer watched.
    const ProviderScope(
      child: PinkRideApp(),
    ),
  );
}

class PinkRideApp extends ConsumerWidget {
  const PinkRideApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the router — it rebuilds when auth state changes
    // (RouterNotifier inside appRouterProvider handles this)
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'PinkRide',
      debugShowCheckedModeBanner: false,

      // Brand theme — all colours, typography, and component styles
      theme: AppTheme.lightTheme,

      // go_router configuration
      routerConfig: router,
    );
  }
}
