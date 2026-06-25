import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/app.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const PersonalButlerApp());
    await tester.pump();
    expect(find.text('个人管家'), findsWidgets);
  });
}
