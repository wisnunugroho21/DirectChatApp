import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tms_connect/api.dart';
import 'package:tms_connect/main.dart';

void main() {
  testWidgets(
    'Login validates required fields and registration exposes profile fields',
    (tester) async {
      final api = Api();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthScreen(api: api, onLogin: () async {}),
        ),
      );
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Required'), findsNWidgets(2));
      await tester.tap(find.text('Create an account'));
      await tester.pump();
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text('Employee ID (optional)'), findsOneWidget);
    },
  );
}
