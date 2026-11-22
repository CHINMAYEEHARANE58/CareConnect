import 'package:careconnect/src/data/care_repository.dart';
import 'package:careconnect/src/data/models.dart';
import 'package:careconnect/src/features/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'upcoming appointment shows clinic location and contact actions',
    (tester) async {
      final start = DateTime.now().add(const Duration(days: 2));
      final appointment = Appointment(
        id: 'appointment',
        clinicId: 'clinic',
        doctorId: 'doctor',
        patientId: 'patient',
        clinicName: 'Willow Clinic',
        clinicAddress: '12 Oak Road',
        clinicCity: 'Bengaluru',
        clinicPhone: '+91 12345 67890',
        clinicEmail: 'hello@willow.example',
        doctorName: 'Dr. Mira Shah',
        startsAt: start,
        endsAt: start.add(const Duration(minutes: 30)),
        status: 'booked',
        cancellationCutoffMinutes: 120,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentsProvider.overrideWith((ref) async => [appointment]),
          ],
          child: const MaterialApp(home: Scaffold(body: AppointmentsTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('12 Oak Road, Bengaluru'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Call clinic'), findsOneWidget);
      expect(find.text('Email clinic'), findsOneWidget);
    },
  );
}
