import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/care_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth_screen.dart';
import 'features/home_screen.dart';
import 'features/booking_screen.dart';
import 'features/clinic_screen.dart';
import 'features/profile_screen.dart';

class AuthRefresh extends ChangeNotifier {
  bool recovery = false;
  AuthRefresh(this.onChange) {
    subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.passwordRecovery) recovery = true;
      if (state.event == AuthChangeEvent.signedOut) recovery = false;
      if (state.event != AuthChangeEvent.tokenRefreshed) onChange();
      notifyListeners();
    });
  }
  final VoidCallback onChange;
  void recoveryCompleted() {
    recovery = false;
    notifyListeners();
  }

  late final StreamSubscription<AuthState> subscription;
  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
}

class CareConnectApp extends ConsumerStatefulWidget {
  const CareConnectApp({super.key});
  @override
  ConsumerState<CareConnectApp> createState() => _CareConnectAppState();
}

class _CareConnectAppState extends ConsumerState<CareConnectApp> {
  late final AuthRefresh refresh;
  @override
  void initState() {
    super.initState();
    refresh = AuthRefresh(() {
      if (!mounted) return;
      for (final provider in [
        clinicsProvider,
        platformClinicsProvider,
        providersProvider,
        availableTodayProvider,
        appointmentsProvider,
        membershipsProvider,
        notificationsProvider,
        profileProvider,
        platformAdminProvider,
      ]) {
        ref.invalidate(provider);
      }
    });
  }

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;
      final authPath =
          state.matchedLocation == '/auth' || state.matchedLocation == '/reset';
      if (user == null && !authPath) return '/auth';
      if (user != null &&
          refresh.recovery &&
          state.matchedLocation != '/change-password') {
        return '/change-password';
      }
      if (user != null && authPath) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
      GoRoute(path: '/auth', builder: (c, s) => const AuthScreen()),
      GoRoute(path: '/reset', builder: (c, s) => const ResetScreen()),
      GoRoute(
        path: '/change-password',
        builder: (c, s) =>
            ChangePasswordScreen(onComplete: refresh.recoveryCompleted),
      ),
      GoRoute(
        path: '/book/:clinic/:doctor',
        builder: (c, s) => BookingScreen(
          clinicId: s.pathParameters['clinic']!,
          doctorId: s.pathParameters['doctor']!,
          appointmentId: s.uri.queryParameters['reschedule'],
        ),
      ),
      GoRoute(
        path: '/clinic/new',
        builder: (c, s) => const RegisterClinicScreen(),
      ),
      GoRoute(
        path: '/clinic/:id',
        builder: (c, s) =>
            ClinicManagementScreen(clinicId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'CareConnect',
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF087E8B),
        primary: const Color(0xFF087E8B),
        secondary: const Color(0xFF278D74),
        surface: const Color(0xFFF7FAF9),
      ),
      scaffoldBackgroundColor: const Color(0xFFF7FAF9),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE0EAE7)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
  );
}
