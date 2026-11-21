import 'package:clinicflow_staff/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text switches to French and fills placeholders', () {
    expect(tr('{n} waiting', {'n': 2}), '2 waiting');
    staffLang.value = 'fr';
    expect(tr('Sign out'), isNot('Sign out'));
    staffLang.value = 'en';
  });
}
