import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  testWidgets('shows setup notice when Firebase is not configured', (tester) async {
    await tester.pumpWidget(const MaaDriverApp(session: null));
    await tester.pumpAndSettle();
    expect(find.textContaining('Firebase'), findsOneWidget);
  });
}
