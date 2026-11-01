import 'package:flutter_test/flutter_test.dart';
import 'package:mymoney/main.dart';

void main() {
  test('money formats whole RWF amounts', () {
    expect(money(10000), '10,000 RWF');
    expect(money(-250), '−250 RWF');
  });
}
