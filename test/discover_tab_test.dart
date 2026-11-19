import 'package:careconnect/src/data/care_repository.dart';
import 'package:careconnect/src/data/models.dart';
import 'package:careconnect/src/features/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('searches clinics and lets patients browse their doctors', (
    tester,
  ) async {
    const clinics = [
      Clinic(
        id: 'willow',
        name: 'Willow Clinic',
        city: 'Bengaluru',
        address: '12 Oak Road',
        timeZone: 'Asia/Kolkata',
        bookingCutoffMinutes: 60,
        cancellationCutoffMinutes: 120,
        active: true,
      ),
      Clinic(
        id: 'harbor',
        name: 'Harbor Clinic',
        city: 'Mumbai',
        address: '8 Coast Road',
        timeZone: 'Asia/Kolkata',
        bookingCutoffMinutes: 60,
        cancellationCutoffMinutes: 120,
        active: true,
      ),
    ];
    const providers = [
      CareProvider(
        id: 'mira',
        clinicId: 'willow',
        name: 'Dr. Mira Shah',
        clinicName: 'Willow Clinic',
        city: 'Bengaluru',
        minutes: 30,
        specialties: ['Family Medicine'],
      ),
      CareProvider(
        id: 'chen',
        clinicId: 'harbor',
        name: 'Dr. Chen',
        clinicName: 'Harbor Clinic',
        city: 'Mumbai',
        minutes: 30,
        specialties: ['Dermatology'],
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicsProvider.overrideWith((ref) async => clinics),
          providersProvider.overrideWith((ref) async => providers),
        ],
        child: const MaterialApp(home: Scaffold(body: DiscoverTab())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Willow');
    await tester.pumpAndSettle();
    expect(find.text('Willow Clinic'), findsOneWidget);
    expect(find.text('Harbor Clinic'), findsNothing);

    await tester.ensureVisible(find.text('Willow Clinic'));
    await tester.tap(find.text('Willow Clinic'));
    await tester.pumpAndSettle();
    expect(find.text('Clinic: Willow Clinic'), findsOneWidget);
    expect(find.text('Dr. Mira Shah'), findsOneWidget);
    expect(find.text('Dr. Chen'), findsNothing);

    await tester.tap(find.byTooltip('Show all clinics'));
    await tester.pumpAndSettle();
    expect(find.text('Dr. Chen'), findsOneWidget);
  });
}
