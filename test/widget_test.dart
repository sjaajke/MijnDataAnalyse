import 'package:flutter_test/flutter_test.dart';
import 'package:mijn_data_analyse/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PqAnalyseApp());
    expect(find.text('PQAnalyse'), findsAny);
  });
}
