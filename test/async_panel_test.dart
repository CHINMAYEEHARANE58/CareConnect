import 'package:careconnect/src/shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading, error and retry affordance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncPanel<String>(value: const AsyncLoading(), data: Text.new),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncPanel<String>(
            value: AsyncError(Exception('offline'), StackTrace.empty),
            data: Text.new,
            onRetry: () => retried = true,
          ),
        ),
      ),
    );
    expect(find.textContaining('Check your connection'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
