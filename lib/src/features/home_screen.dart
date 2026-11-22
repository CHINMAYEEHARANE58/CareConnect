import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/care_repository.dart';
import '../data/models.dart';
import '../shared/ui.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final memberships = ref.watch(membershipsProvider).asData?.value ?? [];
    final platformAdmin =
        ref.watch(platformAdminProvider).asData?.value ?? false;
    final isStaff = memberships.isNotEmpty || platformAdmin;
    final labels = ['Discover', 'Appointments', if (isStaff) 'Clinic', 'Inbox'];
    final icons = [
      Icons.search,
      Icons.event_available_outlined,
      if (isStaff) Icons.medical_services_outlined,
      Icons.notifications_none,
    ];
    if (tab >= labels.length) tab = 0;
    final pages = [
      const DiscoverTab(),
      const AppointmentsTab(),
      if (isStaff)
        platformAdmin
            ? const PlatformTab()
            : ClinicTab(memberships: memberships),
      const InboxTab(),
    ];
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Color(0xFF087E8B)),
            const SizedBox(width: 8),
            const Text('CareConnect'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(
            child: Row(
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: tab,
                    onDestinationSelected: (i) => setState(() => tab = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationRailDestination(
                          icon: Icon(icons[i]),
                          label: Text(labels[i]),
                        ),
                    ],
                  ),
                Expanded(child: pages[tab]),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
    );
  }
}

class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});
  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  String query = '', specialty = 'All';
  String? selectedClinicId;
  bool todayOnly = false;
  final searchController = TextEditingController();
  final scrollController = ScrollController();

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(providersProvider);
    final clinics = ref.watch(clinicsProvider);
    final todayAvailability = todayOnly
        ? ref.watch(availableTodayProvider)
        : null;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(providersProvider);
        ref.invalidate(clinicsProvider);
        ref.invalidate(availableTodayProvider);
        await ref.read(providersProvider.future);
      },
      child: ListView(
        controller: scrollController,
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find care near you',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Explore participating clinics and book a real available time.',
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search doctor, clinic or city',
                  ),
                  onChanged: (v) =>
                      setState(() => query = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                AsyncPanel(
                  value: providers,
                  onRetry: () => ref.invalidate(providersProvider),
                  data: (all) {
                    final specialties = {
                      'All',
                      ...all.expand((p) => p.specialties),
                    }.toList()..sort();
                    final filtered = all.where((p) {
                      final matches =
                          query.isEmpty ||
                          '${p.name} ${p.clinicName} ${p.city} ${p.specialties.join(' ')}'
                              .toLowerCase()
                              .contains(query);
                      return matches &&
                          (selectedClinicId == null ||
                              p.clinicId == selectedClinicId) &&
                          (specialty == 'All' ||
                              p.specialties.contains(specialty)) &&
                          (!todayOnly ||
                              (todayAvailability?.asData?.value.contains(
                                    '${p.clinicId}/${p.id}',
                                  ) ??
                                  false));
                    }).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            if (selectedClinicId != null)
                              InputChip(
                                label: Text(
                                  'Clinic: ${clinics.asData?.value.where((c) => c.id == selectedClinicId).firstOrNull?.name ?? 'Selected'}',
                                ),
                                onDeleted: () =>
                                    setState(() => selectedClinicId = null),
                                deleteButtonTooltipMessage: 'Show all clinics',
                              ),
                            for (final s in specialties)
                              ChoiceChip(
                                label: Text(s),
                                selected: s == specialty,
                                onSelected: (_) =>
                                    setState(() => specialty = s),
                              ),
                            FilterChip(
                              label: const Text('Available today'),
                              selected: todayOnly,
                              onSelected: (value) =>
                                  setState(() => todayOnly = value),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (todayOnly && todayAvailability?.isLoading == true)
                          const LinearProgressIndicator(),
                        if (todayOnly && todayAvailability?.hasError == true)
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(availableTodayProvider),
                            child: const Text(
                              'Could not load availability. Retry',
                            ),
                          ),
                        if (filtered.isEmpty &&
                            todayAvailability?.isLoading != true &&
                            todayAvailability?.hasError != true)
                          const _Empty('No providers match your search.'),
                        for (final p in filtered)
                          Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () =>
                                  context.push('/book/${p.clinicId}/${p.id}'),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: const Color(0xFFDEF3EE),
                                      child: Text(
                                        p.name
                                            .split(' ')
                                            .map(
                                              (e) => e.isNotEmpty ? e[0] : '',
                                            )
                                            .take(2)
                                            .join(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(p.specialties.join(' • ')),
                                          const SizedBox(height: 4),
                                          Text('${p.clinicName} · ${p.city}'),
                                          Text('${p.minutes} min consultation'),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Text('Clinics', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/clinic/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Register your clinic'),
                ),
                const SizedBox(height: 8),
                AsyncPanel(
                  value: clinics,
                  onRetry: () => ref.invalidate(clinicsProvider),
                  data: (all) {
                    final filtered = all.where(
                      (c) =>
                          query.isEmpty ||
                          '${c.name} ${c.city} ${c.address}'
                              .toLowerCase()
                              .contains(query),
                    );
                    if (all.isEmpty) {
                      return const _Empty('No clinics have joined yet.');
                    }
                    if (filtered.isEmpty) {
                      return const _Empty('No clinics match your search.');
                    }
                    return Column(
                      children: [
                        for (final c in filtered)
                          Card(
                            child: ListTile(
                              title: Text(c.name),
                              subtitle: Text('${c.address}, ${c.city}'),
                              leading: const Icon(
                                Icons.local_hospital_outlined,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                setState(() {
                                  selectedClinicId = c.id;
                                  query = '';
                                  searchController.clear();
                                });
                                scrollController.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppointmentsTab extends ConsumerWidget {
  const AppointmentsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(appointmentsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(appointmentsProvider);
        await ref.read(appointmentsProvider.future);
      },
      child: ListView(
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My appointments',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                AsyncPanel(
                  value: value,
                  onRetry: () => ref.invalidate(appointmentsProvider),
                  data: (all) {
                    final upcoming = all
                        .where(
                          (a) =>
                              a.status == 'booked' &&
                              a.endsAt.isAfter(DateTime.now()),
                        )
                        .toList();
                    final past = all
                        .where((a) => !upcoming.contains(a))
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upcoming (${upcoming.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (upcoming.isEmpty)
                          const _Empty('No upcoming appointments.'),
                        for (final a in upcoming)
                          _AppointmentCard(a: a, ref: ref),
                        const SizedBox(height: 20),
                        Text(
                          'History (${past.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (past.isEmpty)
                          const _Empty(
                            'Your past appointments will appear here.',
                          ),
                        for (final a in past) _AppointmentCard(a: a, ref: ref),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.a, required this.ref});
  final Appointment a;
  final WidgetRef ref;

  Future<void> _openLink(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri) && context.mounted) {
        showMessage(context, 'No app is available to open this link.');
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canChange = a.canPatientChangeAt(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.doctorName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(label: Text(a.status)),
              ],
            ),
            Text(a.clinicName),
            Text('${a.clinicAddress}, ${a.clinicCity}'),
            const SizedBox(height: 6),
            Text(
              '${DateFormat('EEE, d MMM yyyy • h:mm a').format(a.startsAt)} ${a.startsAt.timeZoneName}',
            ),
            if (a.status == 'booked' && a.startsAt.isAfter(DateTime.now()))
              Text(
                canChange
                    ? 'Change deadline: ${DateFormat('EEE, d MMM • h:mm a').format(a.patientChangeDeadline)} ${a.patientChangeDeadline.timeZoneName}'
                    : 'Change deadline passed. Contact the clinic if you need help.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (a.status == 'booked' && a.endsAt.isAfter(DateTime.now()))
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _openLink(context, a.directionsUri),
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Directions'),
                  ),
                  if (a.clinicPhone?.trim().isNotEmpty == true)
                    TextButton.icon(
                      onPressed: () => _openLink(
                        context,
                        Uri(scheme: 'tel', path: a.clinicPhone!.trim()),
                      ),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call clinic'),
                    ),
                  if (a.clinicEmail?.trim().isNotEmpty == true)
                    TextButton.icon(
                      onPressed: () => _openLink(
                        context,
                        Uri(scheme: 'mailto', path: a.clinicEmail!.trim()),
                      ),
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Email clinic'),
                    ),
                ],
              ),
            if (canChange)
              Row(
                children: [
                  TextButton(
                    onPressed: () => context.push(
                      '/book/${a.clinicId}/${a.doctorId}?reschedule=${a.id}',
                    ),
                    child: const Text('Reschedule'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Cancel appointment?'),
                          content: const Text(
                            'Clinic cancellation rules apply.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Keep'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Cancel booking'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        try {
                          await ref.read(repositoryProvider).cancel(a.id);
                          ref.invalidate(appointmentsProvider);
                          ref.invalidate(notificationsProvider);
                          ref.invalidate(availableTodayProvider);
                          if (context.mounted) {
                            showMessage(context, 'Appointment cancelled');
                          }
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      }
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class InboxTab extends ConsumerStatefulWidget {
  const InboxTab({super.key});
  @override
  ConsumerState<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends ConsumerState<InboxTab> {
  bool markingAll = false;

  Future<void> markAllRead() async {
    setState(() => markingAll = true);
    try {
      await ref.read(repositoryProvider).markAllNotificationsRead();
      ref.invalidate(notificationsProvider);
      if (mounted) showMessage(context, 'All notifications marked as read');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(notificationsProvider);
    final unread =
        ref.watch(unreadNotificationsProvider).asData?.value ??
        value.asData?.value.where((n) => n['read_at'] == null).length ??
        0;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(notificationsProvider);
        await ref.read(notificationsProvider.future);
      },
      child: ListView(
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (unread > 0)
                      TextButton.icon(
                        onPressed: markingAll ? null : markAllRead,
                        icon: const Icon(Icons.done_all),
                        label: Text(
                          markingAll ? 'Marking...' : 'Mark all read',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                AsyncPanel(
                  value: value,
                  onRetry: () => ref.invalidate(notificationsProvider),
                  data: (rows) => rows.isEmpty
                      ? const _Empty('No notifications yet.')
                      : Column(
                          children: [
                            for (final n in rows)
                              Card(
                                child: ListTile(
                                  leading: Icon(
                                    n['read_at'] == null
                                        ? Icons.notifications_active_outlined
                                        : Icons.notifications_none,
                                  ),
                                  title: Text(n['title'] as String),
                                  subtitle: Text(n['body'] as String),
                                  trailing: Text(
                                    DateFormat('d MMM').format(
                                      DateTime.parse(
                                        n['created_at'] as String,
                                      ).toLocal(),
                                    ),
                                  ),
                                  onTap: () async {
                                    try {
                                      await ref
                                          .read(repositoryProvider)
                                          .markRead(n['id'] as String);
                                      ref.invalidate(notificationsProvider);
                                    } catch (error) {
                                      if (context.mounted) {
                                        showError(context, error);
                                      }
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlatformTab extends ConsumerWidget {
  const PlatformTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    children: [
      PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Platform clinics',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            AsyncPanel(
              value: ref.watch(platformClinicsProvider),
              onRetry: () => ref.invalidate(platformClinicsProvider),
              data: (clinics) => Column(
                children: [
                  for (final clinic in clinics)
                    Card(
                      child: ListTile(
                        title: Text(clinic.name),
                        subtitle: Text(
                          '${clinic.city} • ${clinic.active ? 'Active' : 'Inactive'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/clinic/${clinic.id}'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class ClinicTab extends ConsumerWidget {
  const ClinicTab({super.key, required this.memberships});
  final List<Map<String, dynamic>> memberships;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    children: [
      PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clinic workspace',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final m in memberships)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: Text(
                    (m['clinics'] as Map<String, dynamic>)['name'] as String,
                  ),
                  subtitle: Text(m['role'] as String),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/clinic/${m['clinic_id']}'),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/clinic/new'),
              icon: const Icon(Icons.add),
              label: const Text('Register a clinic'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}
