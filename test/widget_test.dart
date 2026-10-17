import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  testWidgets('driver home renders availability and earnings', (tester) async {
    await tester.pumpWidget(const MaaDriverApp(firebaseReady: false));
    await tester.pumpAndSettle();
    expect(find.text('متاح لاستقبال الطلبات'), findsOneWidget);
    expect(find.text('أرباح اليوم'), findsOneWidget);
  });
}
