import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_compressor/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PdfCompressorApp());
    expect(find.text('Smart PDF Compressor'), findsWidgets);
  });
}
