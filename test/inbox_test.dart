import 'package:careconnect/src/data/care_repository.dart';
import 'package:careconnect/src/features/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepository extends CareRepository {
  _FakeRepository(this.onMarkAll)
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'public-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final Future<void> Function() onMarkAll;

  @override
  Future<void> markAllNotificationsRead() => onMarkAll();
}

void main() {
  testWidgets(
    'mark all read includes unread items beyond the visible inbox page',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var read = false;
      var calls = 0;
      final repository = _FakeRepository(() async {
        calls++;
        read = true;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            notificationsProvider.overrideWith(
              (ref) async => [
                {
                  'id': 'notification',
                  'title': 'Booking confirmed',
                  'body': 'Your appointment is confirmed.',
                  'created_at': '2026-11-22T12:00:00Z',
                  'read_at': '2026-11-22T12:01:00Z',
                  'kind': 'confirmation',
                },
              ],
            ),
            unreadNotificationsProvider.overrideWith((ref) async {
              await ref.watch(notificationsProvider.future);
              return read ? 0 : 1;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: InboxTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mark all read'), findsOneWidget);
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Mark all read'), findsNothing);
      expect(find.text('Booking confirmed'), findsOneWidget);
    },
  );

  testWidgets('mark all read keeps the action when the update fails', (
    tester,
  ) async {
    final repository = _FakeRepository(() async => throw Exception('offline'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          notificationsProvider.overrideWith(
            (ref) async => [
              {
                'id': 'notification',
                'title': 'Booking confirmed',
                'body': 'Your appointment is confirmed.',
                'created_at': '2026-11-22T12:00:00Z',
                'read_at': null,
                'kind': 'confirmation',
              },
            ],
          ),
          unreadNotificationsProvider.overrideWith((ref) async {
            await ref.watch(notificationsProvider.future);
            return 1;
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: InboxTab())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all read'));
    await tester.pump();

    expect(find.text('Mark all read'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });
}
