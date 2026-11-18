import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

final repositoryProvider = Provider<CareRepository>(
  (ref) => CareRepository(Supabase.instance.client),
);
final clinicsProvider = FutureProvider<List<Clinic>>(
  (ref) => ref.watch(repositoryProvider).clinics(),
);
final platformClinicsProvider = FutureProvider<List<Clinic>>(
  (ref) => ref.watch(repositoryProvider).allClinics(),
);
final providersProvider = FutureProvider<List<CareProvider>>(
  (ref) => ref.watch(repositoryProvider).providers(),
);
final availableTodayProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(repositoryProvider).availableTodayKeys(),
);
final appointmentsProvider = FutureProvider<List<Appointment>>(
  (ref) => ref.watch(repositoryProvider).myAppointments(),
);
final membershipsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(repositoryProvider).memberships(),
);
final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(repositoryProvider).notifications(),
);
final platformAdminProvider = FutureProvider<bool>(
  (ref) async =>
      await ref.watch(repositoryProvider).db.rpc('is_platform_admin') as bool,
);
final profileProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(repositoryProvider).profile(),
);

class CareRepository {
  CareRepository(this.db);
  final SupabaseClient db;
  String get userId => db.auth.currentUser!.id;

  Future<List<Clinic>> allClinics() async {
    final rows = await db.from('clinics').select().order('name');
    return rows.map((e) => Clinic.fromJson(e)).toList();
  }

  Future<List<Clinic>> clinics() async {
    final rows = await db
        .from('clinics')
        .select()
        .eq('active', true)
        .order('name');
    return rows.map((e) => Clinic.fromJson(e)).toList();
  }

  Future<List<CareProvider>> providers() async {
    final rows = await db
        .from('doctor_clinics')
        .select(
          'doctor_id,clinic_id,consultation_minutes,doctors!inner(display_name,bio,active,profile_id,doctor_specialties(specialties(name))),clinics!inner(name,city,active)',
        )
        .eq('active', true)
        .eq('doctors.active', true)
        .eq('clinics.active', true);
    return rows.map((e) => CareProvider.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> clinicMetrics(
    String clinicId,
    DateTime day,
  ) async =>
      await db.rpc(
            'clinic_metrics',
            params: {
              'p_clinic': clinicId,
              'p_day':
                  '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
            },
          )
          as Map<String, dynamic>;
  Future<DateTime> clinicToday(String clinicId) async => DateTime.parse(
    await db.rpc('clinic_today', params: {'p_clinic': clinicId}) as String,
  );
  Future<Set<String>> availableTodayKeys() async {
    final rows = await db.rpc('available_today_doctors') as List;
    return rows.map((row) => "${row['clinic_id']}/${row['doctor_id']}").toSet();
  }

  Future<List<Slot>> slots(
    String clinicId,
    String doctorId,
    DateTime day,
  ) async {
    final rows = await db.rpc(
      'available_slots',
      params: {
        'p_clinic': clinicId,
        'p_doctor': doctorId,
        'p_day':
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      },
    );
    return (rows as List)
        .map((e) => Slot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> book(String clinicId, String doctorId, DateTime start) async =>
      await db.rpc(
            'book_appointment',
            params: {
              'p_clinic': clinicId,
              'p_doctor': doctorId,
              'p_start': start.toUtc().toIso8601String(),
            },
          )
          as String;
  Future<void> cancel(String id) async =>
      db.rpc('cancel_appointment', params: {'p_id': id});
  Future<void> reschedule(String id, DateTime start) async => db.rpc(
    'reschedule_appointment',
    params: {'p_id': id, 'p_start': start.toUtc().toIso8601String()},
  );
  Future<void> finish(String id, String state) async =>
      db.rpc('finish_appointment', params: {'p_id': id, 'p_state': state});
  Future<List<Appointment>> myAppointments() async {
    final rows = await db
        .from('appointments')
        .select(
          'id,patient_id,doctor_id,clinic_id,starts_at,ends_at,status,clinics(name),doctors(display_name),profiles!appointments_patient_id_fkey(full_name)',
        )
        .eq('patient_id', userId)
        .order('starts_at', ascending: false);
    return rows.map((e) => Appointment.fromJson(e)).toList();
  }

  Future<List<Appointment>> staffAppointments({
    String? doctorId,
    String? clinicId,
  }) async {
    var query = db
        .from('appointments')
        .select(
          'id,patient_id,doctor_id,clinic_id,starts_at,ends_at,status,clinics(name),doctors(display_name),profiles!appointments_patient_id_fkey(full_name)',
        );
    if (doctorId != null) query = query.eq('doctor_id', doctorId);
    if (clinicId != null) query = query.eq('clinic_id', clinicId);
    final rows = await query
        .gte(
          'starts_at',
          DateTime.now()
              .subtract(const Duration(days: 30))
              .toUtc()
              .toIso8601String(),
        )
        .order('starts_at');
    return rows.map((e) => Appointment.fromJson(e)).toList();
  }

  Future<List<Map<String, dynamic>>> memberships() async => await db
      .from('clinic_memberships')
      .select('clinic_id,role,clinics(name)')
      .eq('user_id', userId);
  Future<List<Map<String, dynamic>>> notifications() async => await db
      .from('notifications')
      .select('id,title,body,created_at,read_at,kind')
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(100);
  Future<void> markRead(String id) async => db
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);
  Future<Map<String, dynamic>> profile() async => await db
      .from('profiles')
      .select('id,full_name,phone,notification_enabled')
      .eq('id', userId)
      .single();
  Future<void> saveProfile(
    String name,
    String phone,
    bool notifications,
  ) async => db
      .from('profiles')
      .update({
        'full_name': name,
        'phone': phone.isEmpty ? null : phone,
        'notification_enabled': notifications,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', userId);
  Future<String> registerClinic({
    required String name,
    required String address,
    required String city,
    required String timeZone,
    String? phone,
  }) async =>
      await db.rpc(
            'register_clinic',
            params: {
              'p_name': name,
              'p_address': address,
              'p_city': city,
              'p_time_zone': timeZone,
              'p_phone': phone,
            },
          )
          as String;
  Future<List<Map<String, dynamic>>> specialties() async =>
      await db.from('specialties').select('id,name').order('name');
  Future<String> addDoctor(
    String clinicId,
    String name,
    String email,
    int specialtyId,
    int minutes,
  ) async =>
      await db.rpc(
            'add_clinic_doctor',
            params: {
              'p_clinic': clinicId,
              'p_name': name,
              'p_email': email,
              'p_specialty_id': specialtyId,
              'p_minutes': minutes,
            },
          )
          as String;
  Future<void> setDoctorActive(
    String clinicId,
    String doctorId,
    bool active,
  ) async => db.rpc(
    'set_doctor_clinic_active',
    params: {'p_clinic': clinicId, 'p_doctor': doctorId, 'p_active': active},
  );
  Future<List<Map<String, dynamic>>> schedules(String clinicId) async =>
      await db
          .from('schedules')
          .select('id,doctor_id,weekday,start_local,end_local')
          .eq('clinic_id', clinicId)
          .order('weekday');
  Future<void> removeSchedule(String scheduleId) async =>
      db.rpc('remove_schedule', params: {'p_schedule': scheduleId});
  Future<void> addSchedule(
    String clinicId,
    String doctorId,
    int weekday,
    String start,
    String end,
  ) async => db.rpc(
    'add_schedule',
    params: {
      'p_clinic': clinicId,
      'p_doctor': doctorId,
      'p_weekday': weekday,
      'p_start': start,
      'p_end': end,
    },
  );
  Future<void> addUnavailability(
    String clinicId,
    String? doctorId,
    DateTime start,
    DateTime end,
    String reason,
  ) async => db.rpc(
    'add_unavailability',
    params: {
      'p_clinic': clinicId,
      'p_doctor': doctorId,
      'p_start': start.toUtc().toIso8601String(),
      'p_end': end.toUtc().toIso8601String(),
      'p_reason': reason,
    },
  );
  Future<void> addDayUnavailability(
    String clinicId,
    String? doctorId,
    DateTime day,
    String reason,
  ) async => db.rpc(
    'add_day_unavailability',
    params: {
      'p_clinic': clinicId,
      'p_doctor': doctorId,
      'p_day':
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      'p_reason': reason,
    },
  );
  Future<void> deleteAccount() async => db.functions.invoke('delete-account');
}
