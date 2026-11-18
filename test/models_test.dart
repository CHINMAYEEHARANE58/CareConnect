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
}
