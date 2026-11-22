class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.timeZone,
    required this.bookingCutoffMinutes,
    required this.cancellationCutoffMinutes,
    required this.active,
    this.description = '',
    this.phone,
    this.email,
  });
  final String id, name, city, address, timeZone, description;
  final String? phone, email;
  final int bookingCutoffMinutes, cancellationCutoffMinutes;
  final bool active;
  factory Clinic.fromJson(Map<String, dynamic> j) => Clinic(
    id: j['id'] as String,
    name: j['name'] as String,
    city: j['city'] as String,
    address: j['address'] as String,
    timeZone: j['time_zone'] as String,
    bookingCutoffMinutes: j['booking_cutoff_minutes'] as int? ?? 60,
    cancellationCutoffMinutes: j['cancellation_cutoff_minutes'] as int? ?? 120,
    active: j['active'] as bool? ?? true,
    description: j['description'] as String? ?? '',
    phone: j['phone'] as String?,
    email: j['email'] as String?,
  );
}

class CareProvider {
  const CareProvider({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.clinicName,
    required this.city,
    required this.minutes,
    required this.specialties,
    this.bio = '',
    this.profileId,
  });
  final String id, clinicId, name, clinicName, city, bio;
  final String? profileId;
  final int minutes;
  final List<String> specialties;
  factory CareProvider.fromJson(Map<String, dynamic> j) {
    final doctor = j['doctors'] as Map<String, dynamic>;
    final clinic = j['clinics'] as Map<String, dynamic>;
    final links = (doctor['doctor_specialties'] as List? ?? []);
    return CareProvider(
      id: j['doctor_id'] as String,
      clinicId: j['clinic_id'] as String,
      name: doctor['display_name'] as String,
      profileId: doctor['profile_id'] as String?,
      clinicName: clinic['name'] as String,
      city: clinic['city'] as String,
      bio: doctor['bio'] as String? ?? '',
      minutes: j['consultation_minutes'] as int,
      specialties: links
          .map(
            (e) => (e['specialties'] as Map<String, dynamic>)['name'] as String,
          )
          .toList(),
    );
  }
}

class Appointment {
  const Appointment({
    required this.id,
    required this.clinicId,
    required this.doctorId,
    required this.patientId,
    required this.clinicName,
    required this.clinicAddress,
    required this.clinicCity,
    required this.doctorName,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.cancellationCutoffMinutes,
    this.clinicPhone,
    this.clinicEmail,
    this.patientName,
  });
  final String id,
      clinicId,
      doctorId,
      patientId,
      clinicName,
      clinicAddress,
      clinicCity,
      doctorName,
      status;
  final String? patientName, clinicPhone, clinicEmail;
  final DateTime startsAt, endsAt;
  final int cancellationCutoffMinutes;
  Uri get directionsUri => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$clinicName, $clinicAddress, $clinicCity',
  });
  DateTime get patientChangeDeadline =>
      startsAt.subtract(Duration(minutes: cancellationCutoffMinutes));
  bool canPatientChangeAt(DateTime now) =>
      status == 'booked' && !now.isAfter(patientChangeDeadline);
  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
    id: j['id'] as String,
    clinicId: j['clinic_id'] as String,
    doctorId: j['doctor_id'] as String,
    patientId: j['patient_id'] as String,
    clinicName: (j['clinics'] as Map<String, dynamic>)['name'] as String,
    clinicAddress: (j['clinics'] as Map<String, dynamic>)['address'] as String,
    clinicCity: (j['clinics'] as Map<String, dynamic>)['city'] as String,
    clinicPhone: (j['clinics'] as Map<String, dynamic>)['phone'] as String?,
    clinicEmail: (j['clinics'] as Map<String, dynamic>)['email'] as String?,
    doctorName:
        (j['doctors'] as Map<String, dynamic>)['display_name'] as String,
    patientName:
        (j['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    endsAt: DateTime.parse(j['ends_at'] as String).toLocal(),
    status: j['status'] as String,
    cancellationCutoffMinutes:
        (j['clinics'] as Map<String, dynamic>)['cancellation_cutoff_minutes']
            as int,
  );
}

class Slot {
  const Slot(this.start, this.end);
  final DateTime start, end;
  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
    DateTime.parse(j['starts_at'] as String).toLocal(),
    DateTime.parse(j['ends_at'] as String).toLocal(),
  );
}
