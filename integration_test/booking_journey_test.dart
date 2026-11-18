import 'package:careconnect/src/data/care_repository.dart';
import 'package:careconnect/src/data/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Run against a disposable Supabase project with seed.sql loaded and a confirmed test patient.
// Credentials come from dart-define; never commit them.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const email = String.fromEnvironment('TEST_PATIENT_EMAIL');
  const password = String.fromEnvironment('TEST_PATIENT_PASSWORD');
  testWidgets(
    'patient finds a slot, books and cancels',
    (tester) async {
      await Supabase.initialize(url: url, publishableKey: key);
      final db = Supabase.instance.client;
      await db.auth.signInWithPassword(email: email, password: password);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repository = container.read(repositoryProvider);
      final providers = await repository.providers();
      expect(providers, isNotEmpty);
      final CareProvider provider = providers.first;
      Slot? slot;
      for (var i = 1; i < 15 && slot == null; i++) {
        final day = DateTime.now().add(Duration(days: i));
        final slots = await repository.slots(
          provider.clinicId,
          provider.id,
          day,
        );
        if (slots.isNotEmpty) slot = slots.first;
      }
      expect(slot, isNotNull);
      final id = await repository.book(
        provider.clinicId,
        provider.id,
        slot!.start,
      );
      final appointments = await repository.myAppointments();
      expect(
        appointments.any((a) => a.id == id && a.status == 'booked'),
        isTrue,
      );
      await repository.cancel(id);
      final updated = await repository.myAppointments();
      expect(updated.singleWhere((a) => a.id == id).status, 'cancelled');
      await db.auth.signOut();
    },
    skip: url.isEmpty || key.isEmpty || email.isEmpty || password.isEmpty,
  );
}
