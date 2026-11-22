import 'package:careconnect/src/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider parses clinic and specialties', () {
    final provider = CareProvider.fromJson({
      'doctor_id': 'doctor',
      'clinic_id': 'clinic',
      'consultation_minutes': 30,
      'doctors': {
        'display_name': 'Dr. Mira Shah',
        'bio': 'Family care',
        'profile_id': null,
        'doctor_specialties': [
          {
            'specialties': {'name': 'Family Medicine'},
          },
        ],
      },
      'clinics': {'name': 'Willow', 'city': 'Bengaluru'},
    });
    expect(provider.name, 'Dr. Mira Shah');
    expect(provider.specialties, ['Family Medicine']);
    expect(provider.minutes, 30);
  });
  test('slot preserves UTC instant while presenting local time', () {
    final slot = Slot.fromJson({
      'starts_at': '2026-11-01T05:30:00Z',
      'ends_at': '2026-11-01T06:00:00Z',
    });
    expect(slot.start.toUtc().toIso8601String(), '2026-11-01T05:30:00.000Z');
    expect(slot.end.difference(slot.start), const Duration(minutes: 30));
  });
  test('appointment applies the clinic change cutoff at the boundary', () {
    final appointment = Appointment.fromJson({
      'id': 'appointment',
      'clinic_id': 'clinic',
      'doctor_id': 'doctor',
      'patient_id': 'patient',
      'starts_at': '2026-12-01T12:00:00Z',
      'ends_at': '2026-12-01T12:30:00Z',
      'status': 'booked',
      'clinics': {
        'name': 'Willow',
        'address': '12 Oak Road',
        'city': 'Bengaluru',
        'phone': '+91 12345 67890',
        'email': 'hello@willow.example',
        'cancellation_cutoff_minutes': 120,
      },
      'doctors': {'display_name': 'Dr. Mira Shah'},
    });
    expect(
      appointment.patientChangeDeadline.toUtc(),
      DateTime.utc(2026, 12, 1, 10),
    );
    expect(
      appointment.canPatientChangeAt(DateTime.utc(2026, 12, 1, 9, 59)),
      isTrue,
    );
    expect(
      appointment.canPatientChangeAt(DateTime.utc(2026, 12, 1, 10)),
      isTrue,
    );
    expect(
      appointment.canPatientChangeAt(DateTime.utc(2026, 12, 1, 10, 1)),
      isFalse,
    );
    expect(appointment.clinicPhone, '+91 12345 67890');
    expect(appointment.clinicEmail, 'hello@willow.example');
    expect(appointment.directionsUri.scheme, 'https');
    expect(appointment.directionsUri.path, '/maps/dir/');
    expect(appointment.directionsUri.queryParameters, {
      'api': '1',
      'destination': 'Willow, 12 Oak Road, Bengaluru',
    });
  });
}
