import 'package:careconnect/src/data/care_repository.dart';
import 'package:careconnect/src/features/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'unread notification count appears on phone and tablet navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            membershipsProvider.overrideWith((ref) async => []),
            platformAdminProvider.overrideWith((ref) async => false),
            providersProvider.overrideWith((ref) async => []),
            clinicsProvider.overrideWith((ref) async => []),
            notificationsProvider.overrideWith((ref) async => []),
            unreadNotificationsProvider.overrideWith((ref) async => 3),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      tester.view.physicalSize = const Size(1000, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    },
  );
}
