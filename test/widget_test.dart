import 'package:flutter_test/flutter_test.dart';
import 'package:textora_dialer/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TextoraDialerApp());
    expect(find.byType(TextoraDialerApp), findsOneWidget);
  });
}
