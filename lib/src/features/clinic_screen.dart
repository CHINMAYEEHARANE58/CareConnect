import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/care_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models.dart';
import '../shared/ui.dart';

class RegisterClinicScreen extends ConsumerStatefulWidget {
  const RegisterClinicScreen({super.key});
  @override
  ConsumerState<RegisterClinicScreen> createState() =>
      _RegisterClinicScreenState();
}

class _RegisterClinicScreenState extends ConsumerState<RegisterClinicScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      address = TextEditingController(),
      city = TextEditingController(),
      phone = TextEditingController(),
      zone = TextEditingController(text: 'Asia/Kolkata');
  bool busy = false;
  @override
  void dispose() {
    for (final c in [name, address, city, phone, zone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Register clinic')),
    body: PageFrame(
      child: ListView(
        children: [
          Text(
            'Bring your clinic online',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'You will become this clinic’s administrator. Use an IANA time zone such as Asia/Kolkata.',
          ),
          const SizedBox(height: 20),
          Form(
            key: form,
            child: Column(
              children: [
                for (final item in [
                  (name, 'Clinic name'),
                  (address, 'Address'),
                  (city, 'City'),
                  (zone, 'Time zone'),
                ]) ...[
                  TextFormField(
                    controller: item.$1,
                    decoration: InputDecoration(labelText: item.$2),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          setState(() => busy = true);
                          try {
                            final id = await ref
                                .read(repositoryProvider)
                                .registerClinic(
                                  name: name.text.trim(),
                                  address: address.text.trim(),
                                  city: city.text.trim(),
                                  timeZone: zone.text.trim(),
                                  phone: phone.text.trim(),
                                );
                            ref.invalidate(membershipsProvider);
                            ref.invalidate(clinicsProvider);
                            if (context.mounted) context.go('/clinic/$id');
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: Text(busy ? 'Creating...' : 'Create clinic'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ClinicManagementScreen extends ConsumerStatefulWidget {
  const ClinicManagementScreen({super.key, required this.clinicId});
  final String clinicId;
  @override
  ConsumerState<ClinicManagementScreen> createState() =>
      _ClinicManagementScreenState();
}

class _ClinicManagementScreenState
    extends ConsumerState<ClinicManagementScreen> {
  int dayOffset = 0;
  Future<Map<String, dynamic>>? metrics;
  Future<Map<String, dynamic>> _loadMetrics() async {
    final repo = ref.read(repositoryProvider);
    final today = await repo.clinicToday(widget.clinicId);
    return repo.clinicMetrics(widget.clinicId, today);
  }

  late Future<List<Map<String, dynamic>>> schedules = ref
      .read(repositoryProvider)
      .schedules(widget.clinicId);
  late Future<List<Appointment>> appointments = ref
      .read(repositoryProvider)
      .staffAppointments(clinicId: widget.clinicId);
  void reload() {
    setState(() {
      appointments = ref
          .read(repositoryProvider)
          .staffAppointments(clinicId: widget.clinicId);
      if (metrics != null) metrics = _loadMetrics();
      schedules = ref.read(repositoryProvider).schedules(widget.clinicId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final providers =
        ref
            .watch(providersProvider)
            .asData
            ?.value
            .where((p) => p.clinicId == widget.clinicId)
            .toList() ??
        [];
    final member =
        ref
            .watch(membershipsProvider)
            .asData
            ?.value
            .where((m) => m['clinic_id'] == widget.clinicId)
            .toList() ??
        [];
    final platformAdmin =
        ref.watch(platformAdminProvider).asData?.value ?? false;
    final admin =
        member.any((m) => m['role'] == 'clinic_admin') || platformAdmin;
    if (admin) metrics ??= _loadMetrics();
    final myDoctor = providers
        .where(
          (p) => p.profileId == Supabase.instance.client.auth.currentUser?.id,
        )
        .firstOrNull;
    final clinic = ref
        .watch(platformAdmin ? platformClinicsProvider : clinicsProvider)
        .asData
        ?.value
        .where((c) => c.id == widget.clinicId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(clinic?.name ?? 'Clinic workspace')),
      body: PageFrame(
        child: ListView(
          children: [
            if (clinic != null)
              Text('${clinic.address}, ${clinic.city} • ${clinic.timeZone}'),
            const SizedBox(height: 16),
            if (admin) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _addDoctor(context),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add doctor'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _addSchedule(context, providers),
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Add hours'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _unavailable(context, providers),
                    icon: const Icon(Icons.event_busy),
                    label: const Text('Block time'),
                  ),
                  if (platformAdmin && clinic != null && !clinic.active)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          await ref
                              .read(repositoryProvider)
                              .db
                              .from('clinics')
                              .update({'active': true})
                              .eq('id', clinic.id);
                          ref.invalidate(clinicsProvider);
                          ref.invalidate(platformClinicsProvider);
                          ref.invalidate(providersProvider);
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Reactivate'),
                    ),
                  if (clinic != null)
                    FilledButton.tonalIcon(
                      onPressed: () => _editClinic(context, clinic),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit clinic'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (!admin && myDoctor != null) ...[
              FilledButton.tonalIcon(
                onPressed: () =>
                    _unavailable(context, [myDoctor], doctorOnly: true),
                icon: const Icon(Icons.event_busy),
                label: const Text('Add unavailability'),
              ),
              const SizedBox(height: 16),
            ],
            Text('Doctors', style: Theme.of(context).textTheme.titleLarge),
            for (final p in providers)
              Card(
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.specialties.join(', ')} • ${p.minutes} min',
                  ),
                  trailing: admin
                      ? PopupMenuButton<String>(
                          tooltip: 'Manage doctor',
                          onSelected: (choice) async {
                            if (choice != 'deactivate') return;
                            try {
                              await ref
                                  .read(repositoryProvider)
                                  .setDoctorActive(
                                    widget.clinicId,
                                    p.id,
                                    false,
                                  );
                              ref.invalidate(providersProvider);
                              ref.invalidate(availableTodayProvider);
                              reload();
                            } catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'deactivate',
                              child: Text('Deactivate at clinic'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            const SizedBox(height: 16),
            Text('Weekly hours', style: Theme.of(context).textTheme.titleLarge),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: schedules,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return snapshot.hasError
                      ? const Text('Could not load hours.')
                      : const LinearProgressIndicator();
                }
                if (snapshot.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No weekly hours yet.'),
                  );
                }
                return Column(
                  children: [
                    for (final schedule in snapshot.data!)
                      Card(
                        child: ListTile(
                          title: Text(
                            '${['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][schedule['weekday'] as int]} • ${schedule['start_local']}–${schedule['end_local']}',
                          ),
                          subtitle: Text(
                            providers
                                    .where((p) => p.id == schedule['doctor_id'])
                                    .firstOrNull
                                    ?.name ??
                                'Doctor',
                          ),
                          trailing: admin
                              ? IconButton(
                                  tooltip: 'Remove hours',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(repositoryProvider)
                                          .removeSchedule(
                                            schedule['id'] as String,
                                          );
                                      ref.invalidate(availableTodayProvider);
                                      reload();
                                    } catch (e) {
                                      if (context.mounted) {
                                        showError(context, e);
                                      }
                                    }
                                  },
                                )
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (admin)
              FutureBuilder<Map<String, dynamic>>(
                future: metrics,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return snapshot.hasError
                        ? const Text('Analytics unavailable.')
                        : const LinearProgressIndicator();
                  }
                  final m = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today’s capacity',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          _Metric('Booked', '${m['booked']}'),
                          _Metric('Available', '${m['available']}'),
                          _Metric('Utilization', '${m['utilization']}%'),
                          _Metric(
                            'Cancellation rate',
                            '${m['cancellation_rate']}%',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            FutureBuilder<List<Appointment>>(
              future: appointments,
              builder: (context, s) {
                if (!s.hasData) {
                  return s.hasError
                      ? const Text('Could not load appointments.')
                      : const Center(child: CircularProgressIndicator());
                }
                final all = s.data!;
                final today = all
                    .where(
                      (a) => DateUtils.isSameDay(a.startsAt, DateTime.now()),
                    )
                    .toList();
                final week = all
                    .where(
                      (a) =>
                          a.startsAt.isAfter(
                            DateTime.now().subtract(const Duration(days: 1)),
                          ) &&
                          a.startsAt.isBefore(
                            DateTime.now().add(const Duration(days: 7)),
                          ),
                    )
                    .toList();
                final cancelled = all
                    .where((a) => a.status == 'cancelled')
                    .length;
                final booked = all.where((a) => a.status == 'booked').length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overview',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        _Metric('Today', today.length.toString()),
                        _Metric('Booked', booked.toString()),
                        _Metric('Cancelled', cancelled.toString()),
                        _Metric(
                          'Cancellation rate',
                          all.isEmpty
                              ? '0%'
                              : '${(cancelled / all.length * 100).round()}%',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Weekly calendar',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 7,
                        itemBuilder: (context, i) {
                          final day = DateTime.now().add(Duration(days: i));
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(DateFormat('EEE d MMM').format(day)),
                              selected: dayOffset == i,
                              onSelected: (_) => setState(() => dayOffset = i),
                            ),
                          );
                        },
                      ),
                    ),
                    if (week
                        .where(
                          (a) => DateUtils.isSameDay(
                            a.startsAt,
                            DateTime.now().add(Duration(days: dayOffset)),
                          ),
                        )
                        .isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No scheduled appointments.'),
                      ),
                    for (final a in week.where(
                      (a) => DateUtils.isSameDay(
                        a.startsAt,
                        DateTime.now().add(Duration(days: dayOffset)),
                      ),
                    ))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.doctorName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                DateFormat(
                                  'EEE, d MMM • h:mm a',
                                ).format(a.startsAt),
                              ),
                              Text(
                                'Patient: ${a.patientName?.isNotEmpty == true ? a.patientName : 'Name unavailable'}',
                              ),
                              Text('Status: ${a.status}'),
                              if (a.status == 'booked' &&
                                  a.startsAt.isBefore(DateTime.now()))
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: () => _finish(a, 'completed'),
                                      child: const Text('Mark completed'),
                                    ),
                                    TextButton(
                                      onPressed: () => _finish(a, 'no_show'),
                                      child: const Text('No-show'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish(Appointment a, String state) async {
    try {
      await ref.read(repositoryProvider).finish(a.id, state);
      reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _addDoctor(BuildContext context) async {
    final name = TextEditingController(),
        email = TextEditingController(),
        minutes = TextEditingController(text: '30');
    final specs = await ref.read(repositoryProvider).specialties();
    if (!context.mounted) return;
    int? specialty = specs.isEmpty ? null : specs.first['id'] as int;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Add doctor'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The doctor must register and verify this email first.',
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(
                    labelText: 'Verified email',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: specialty,
                  items: [
                    for (final s in specs)
                      DropdownMenuItem(
                        value: s['id'] as int,
                        child: Text(s['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => specialty = v),
                  decoration: const InputDecoration(labelText: 'Specialty'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Consultation minutes',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: specialty == null
                  ? null
                  : () async {
                      try {
                        await ref
                            .read(repositoryProvider)
                            .addDoctor(
                              widget.clinicId,
                              name.text.trim(),
                              email.text.trim(),
                              specialty!,
                              int.parse(minutes.text),
                            );
                        ref.invalidate(providersProvider);
                        ref.invalidate(availableTodayProvider);
                        reload();
                        if (c.mounted) Navigator.pop(c);
                      } catch (e) {
                        if (c.mounted) showError(c, e);
                      }
                    },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    email.dispose();
    minutes.dispose();
  }

  Future<void> _addSchedule(
    BuildContext context,
    List<CareProvider> providers,
  ) async {
    if (providers.isEmpty) {
      showMessage(context, 'Add a doctor first.');
      return;
    }
    String doctor = providers.first.id;
    int weekday = DateTime.monday;
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0),
        end = const TimeOfDay(hour: 17, minute: 0);
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Weekly hours'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: doctor,
                  items: [
                    for (final p in providers)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setLocal(() => doctor = v!),
                  decoration: const InputDecoration(labelText: 'Doctor'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: weekday,
                  items: [
                    for (var i = 1; i <= 7; i++)
                      DropdownMenuItem(
                        value: i % 7,
                        child: Text(
                          [
                            'Sunday',
                            'Monday',
                            'Tuesday',
                            'Wednesday',
                            'Thursday',
                            'Friday',
                            'Saturday',
                          ][i % 7],
                        ),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => weekday = v!),
                  decoration: const InputDecoration(labelText: 'Day'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Start: ${start.format(c)}'),
                  onTap: () async {
                    final x = await showTimePicker(
                      context: c,
                      initialTime: start,
                    );
                    if (x != null) setLocal(() => start = x);
                  },
                ),
                ListTile(
                  title: Text('End: ${end.format(c)}'),
                  onTap: () async {
                    final x = await showTimePicker(
                      context: c,
                      initialTime: end,
                    );
                    if (x != null) setLocal(() => end = x);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                String fmt(TimeOfDay t) =>
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
                try {
                  await ref
                      .read(repositoryProvider)
                      .addSchedule(
                        widget.clinicId,
                        doctor,
                        weekday,
                        fmt(start),
                        fmt(end),
                      );
                  if (c.mounted) {
                    Navigator.pop(c);
                    ref.invalidate(availableTodayProvider);
                    reload();
                    showMessage(context, 'Hours saved');
                  }
                } catch (e) {
                  if (c.mounted) showError(c, e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unavailable(
    BuildContext context,
    List<CareProvider> providers, {
    bool doctorOnly = false,
  }) async {
    DateTime day = DateTime.now();
    String? doctor = doctorOnly ? providers.first.id : null;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Block a day'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Blocks all appointments at this clinic for the selected day, or only one doctor.',
              ),
              DropdownButtonFormField<String>(
                initialValue: doctor,
                items: [
                  if (!doctorOnly)
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Entire clinic'),
                    ),
                  for (final p in providers)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setLocal(() => doctor = v),
                decoration: const InputDecoration(labelText: 'Applies to'),
              ),
              ListTile(
                title: Text(DateFormat('d MMM yyyy').format(day)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final x = await showDatePicker(
                    context: c,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: day,
                  );
                  if (x != null) setLocal(() => day = x);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(repositoryProvider)
                      .addDayUnavailability(
                        widget.clinicId,
                        doctor,
                        day,
                        'Unavailable',
                      );
                  if (c.mounted) {
                    Navigator.pop(c);
                    ref.invalidate(availableTodayProvider);
                    reload();
                    showMessage(context, 'Day blocked');
                  }
                } catch (e) {
                  if (c.mounted) showError(c, e);
                }
              },
              child: const Text('Block'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editClinic(BuildContext context, Clinic clinic) async {
    final name = TextEditingController(text: clinic.name);
    final address = TextEditingController(text: clinic.address);
    final city = TextEditingController(text: clinic.city);
    final description = TextEditingController(text: clinic.description);
    final phone = TextEditingController(text: clinic.phone ?? '');
    final email = TextEditingController(text: clinic.email ?? '');
    final zone = TextEditingController(text: clinic.timeZone);
    final bookingCutoff = TextEditingController(
      text: '${clinic.bookingCutoffMinutes}',
    );
    final cancellationCutoff = TextEditingController(
      text: '${clinic.cancellationCutoffMinutes}',
    );
    final fields = [
      name,
      address,
      city,
      description,
      phone,
      email,
      zone,
      bookingCutoff,
      cancellationCutoff,
    ];
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clinic profile and rules'),
        content: SizedBox(
          width: 460,
          height: 470,
          child: ListView(
            children: [
              for (final field in [
                (name, 'Name'),
                (address, 'Address'),
                (city, 'City'),
                (description, 'Description'),
                (phone, 'Phone'),
                (email, 'Email'),
                (zone, 'IANA time zone'),
                (bookingCutoff, 'Booking cutoff (minutes)'),
                (cancellationCutoff, 'Cancel and reschedule cutoff (minutes)'),
              ]) ...[
                TextField(
                  controller: field.$1,
                  decoration: InputDecoration(labelText: field.$2),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final bookMinutes = int.tryParse(bookingCutoff.text);
              final cancelMinutes = int.tryParse(cancellationCutoff.text);
              if (name.text.trim().length < 2 ||
                  address.text.trim().isEmpty ||
                  city.text.trim().isEmpty ||
                  bookMinutes == null ||
                  cancelMinutes == null ||
                  bookMinutes < 0 ||
                  cancelMinutes < 0) {
                showMessage(
                  c,
                  'Complete the required fields and use nonnegative cutoff minutes.',
                );
                return;
              }
              try {
                await ref
                    .read(repositoryProvider)
                    .db
                    .from('clinics')
                    .update({
                      'name': name.text.trim(),
                      'address': address.text.trim(),
                      'city': city.text.trim(),
                      'description': description.text.trim(),
                      'phone': phone.text.trim(),
                      'email': email.text.trim(),
                      'time_zone': zone.text.trim(),
                      'booking_cutoff_minutes': bookMinutes,
                      'cancellation_cutoff_minutes': cancelMinutes,
                    })
                    .eq('id', widget.clinicId);
                ref.invalidate(clinicsProvider);
                ref.invalidate(platformClinicsProvider);
                if (c.mounted) Navigator.pop(c);
              } catch (e) {
                if (c.mounted) showError(c, e);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    for (final field in fields) {
      field.dispose();
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    ),
  );
}
