import 'package:careconnect/src/features/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login validates credentials before requesting authentication', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
  });
  testWidgets('registration collects a name and checks it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.tap(find.text('Create an account'));
    await tester.pump();
    expect(find.text('Full name'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
  });
}
