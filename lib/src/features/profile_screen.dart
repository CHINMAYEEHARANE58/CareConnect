import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/care_repository.dart';
import '../shared/ui.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final name = TextEditingController(), phone = TextEditingController();
  bool notifications = true, initialized = false, busy = false;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: PageFrame(
        child: ListView(
          children: [
            AsyncPanel(
              value: profile,
              onRetry: () => ref.invalidate(profileProvider),
              data: (p) {
                if (!initialized) {
                  name.text = p['full_name'] as String? ?? '';
                  phone.text = p['phone'] as String? ?? '';
                  notifications = p['notification_enabled'] as bool? ?? true;
                  initialized = true;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Supabase.instance.client.auth.currentUser?.email ?? '',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Appointment notifications'),
                      subtitle: const Text('Booking updates and reminders'),
                      value: notifications,
                      onChanged: (v) => setState(() => notifications = v),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                await ref
                                    .read(repositoryProvider)
                                    .saveProfile(
                                      name.text.trim(),
                                      phone.text.trim(),
                                      notifications,
                                    );
                                ref.invalidate(profileProvider);
                                if (context.mounted) {
                                  showMessage(context, 'Profile saved');
                                }
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      child: const Text('Save profile'),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                        if (context.mounted) context.go('/auth');
                      },
                      child: const Text('Sign out'),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete account?'),
                            content: const Text(
                              'Your account and scheduling profile will be removed. Future bookings will be cancelled. This cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Keep account'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          try {
                            await ref.read(repositoryProvider).deleteAccount();
                            await Supabase.instance.client.auth.signOut();
                            if (context.mounted) context.go('/auth');
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        }
                      },
                      child: const Text('Delete my account'),
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
}
