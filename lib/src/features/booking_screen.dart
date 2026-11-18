import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/care_repository.dart';
import '../data/models.dart';
import '../shared/ui.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({
    super.key,
    required this.clinicId,
    required this.doctorId,
    this.appointmentId,
  });
  final String clinicId, doctorId;
  final String? appointmentId;
  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  DateTime day = DateUtils.dateOnly(DateTime.now());
  DateTime baseDay = DateUtils.dateOnly(DateTime.now());
  Slot? selected;
  bool busy = false;
  bool? verifiedOverride;
  Future<List<Slot>> load() =>
      ref.read(repositoryProvider).slots(widget.clinicId, widget.doctorId, day);
  late Future<List<Slot>> future = load();
  @override
  void initState() {
    super.initState();
    ref
        .read(repositoryProvider)
        .clinicToday(widget.clinicId)
        .then((clinicDay) {
          if (mounted) {
            setState(() {
              baseDay = clinicDay;
              day = clinicDay;
              selected = null;
              future = load();
            });
          }
        })
        .catchError((_) {});
  }

  void chooseDay(DateTime value) => setState(() {
    day = DateUtils.dateOnly(value);
    selected = null;
    future = load();
  });

  Future<void> submit() async {
    if (selected == null) return;
    setState(() => busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      if (widget.appointmentId == null) {
        await repo.book(widget.clinicId, widget.doctorId, selected!.start);
      } else {
        await repo.reschedule(widget.appointmentId!, selected!.start);
      }
      ref.invalidate(appointmentsProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(availableTodayProvider);
      if (mounted) {
        showMessage(
          context,
          widget.appointmentId == null
              ? 'Appointment confirmed'
              : 'Appointment rescheduled',
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() {
          selected = null;
          future = load();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref
        .watch(providersProvider)
        .asData
        ?.value
        .where((p) => p.id == widget.doctorId && p.clinicId == widget.clinicId)
        .firstOrNull;
    final verified =
        verifiedOverride ??
        (Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.appointmentId == null ? 'Book appointment' : 'Reschedule',
        ),
      ),
      body: PageFrame(
        child: ListView(
          children: [
            if (provider != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(provider.specialties.join(' • ')),
                      const SizedBox(height: 8),
                      Text('${provider.clinicName} · ${provider.city}'),
                      Text('${provider.minutes} minute consultation'),
                      if (provider.bio.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(provider.bio),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Text('Choose a day', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 78,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 30,
                itemBuilder: (context, index) {
                  final d = DateUtils.dateOnly(
                    baseDay.add(Duration(days: index)),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateFormat('EEE').format(d)),
                          Text(DateFormat('d MMM').format(d)),
                        ],
                      ),
                      selected: DateUtils.isSameDay(d, day),
                      onSelected: (_) => chooseDay(d),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Available times',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Times shown in your device time zone (${DateTime.now().timeZoneName}).',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Slot>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text('Could not load slots.'),
                      TextButton(
                        onPressed: () => setState(() => future = load()),
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                final slots = snapshot.data ?? [];
                if (slots.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No available times for this day. Try another date.',
                    ),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in slots)
                      ChoiceChip(
                        label: Text(
                          "${DateFormat('h:mm a').format(slot.start)} ${slot.start.timeZoneName}",
                        ),
                        selected: selected?.start == slot.start,
                        onSelected: (_) => setState(() => selected = slot),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 30),
            if (!verified)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Verify your email before booking. Open the verification link in your email, then return to the app.',
                  ),
                ),
              ),
            if (!verified)
              TextButton(
                onPressed: () async {
                  try {
                    final response = await Supabase.instance.client.auth
                        .getUser();
                    if (context.mounted) {
                      setState(
                        () => verifiedOverride =
                            response.user?.emailConfirmedAt != null,
                      );
                    }
                    if (context.mounted && verifiedOverride == false) {
                      showMessage(context, 'Your email is not verified yet.');
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('I verified my email — refresh'),
              ),
            FilledButton(
              onPressed: busy || selected == null || !verified ? null : submit,
              child: Text(
                busy
                    ? 'Please wait...'
                    : widget.appointmentId == null
                    ? 'Confirm booking'
                    : 'Confirm new time',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No payment is required to book.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
