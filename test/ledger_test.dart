import 'package:flutter_test/flutter_test.dart';
import 'package:mymoney/models/ledger.dart';
import 'package:mymoney/services/lab12.dart';

void main() {
  test('Lab 12 scenario has exact expected output', () {
    expect(runLab12Scenario(), [
      'Received 50000 RWF in MoMo',
      'Spent 3500 RWF on food from MoMo',
      'Received 10000 RWF in Cash',
      'Holding 20000 RWF for Eric in Bank',
      'Spent 1200 RWF on transport from Cash',
      'Returned 5000 RWF to Eric from Bank',
      'Refused: Insufficient personal balance in Cash',
      'Refused: Cannot return more than owed to Eric in Bank',
      'Summary: Cash 8800, MoMo 46500, Bank 15000 RWF',
      'Unknown command: fly:momo:1000',
    ]);
  });
  test('held funds do not count as personal income or available money', () {
    final l = MoneyLedger(opening: {'Cash': 100});
    l.add('hold', 'Cash', 5000, person: 'Eric');
    expect(l.balance('Cash'), 5100);
    expect(l.heldTotal, 5000);
    expect(l.available, 100);
    expect(l.totalFor('income'), 0);
    expect(() => l.add('expense', 'Cash', 101, category: 'Food'), throwsA(isA<LedgerException>()));
    l.add('return', 'Cash', 2000, person: 'Eric');
    expect(l.held('Eric'), 3000);
  });
  test('budgets goals and serialized data are restored correctly', () {
    final l = MoneyLedger(opening: {'Cash': 10000});
    l.add('expense', 'Cash', 2500, category: 'Food');
    l.createGoal('Laptop', 20000);
    l.saveForGoal(l.goals.single.id, 3000);
    l.setBudget('Food', 5000);
    final r = MoneyLedger.decode(l.encode());
    expect(r.available, 4500);
    expect(r.goals.single.saved, 3000);
    expect(r.totalFor('expense', category: 'Food'), 2500);
    expect(r.budgets['Food'], 5000);
  });
  test('deletion that breaks a subsequent return is refused and reverted', () {
    final l = MoneyLedger();
    l.add('hold', 'Cash', 5000, person: 'Eric');
    final id = l.events.single.id;
    l.add('return', 'Cash', 2500, person: 'Eric');
    expect(() => l.delete(id), throwsA(isA<LedgerException>()));
    expect(l.events.length, 2);
  });
  test('editing an entry recalculates and an invalid edit is refused', () {
    final l = MoneyLedger();
    l.add('income', 'Cash', 5000);
    l.add('expense', 'Cash', 1000, category: 'Food');
    final id = l.events.last.id;
    l.replace(id, kind: 'expense', account: 'Cash', amount: 2000, category: 'Food');
    expect(l.balance('Cash'), 3000);
    expect(() => l.replace(id, kind: 'expense', account: 'Cash', amount: 9000, category: 'Food'),
        throwsA(isA<LedgerException>()));
    expect(l.balance('Cash'), 3000);
    expect(l.events.last.amount, 2000);
  });
  test('valid deletions recalculate totals', () {
    final l = MoneyLedger();
    l.add('income', 'Cash', 9000);
    l.add('expense', 'Cash', 1500, category: 'Food');
    l.delete(l.events.last.id);
    expect(l.balance('Cash'), 9000);
    expect(l.totalFor('expense'), 0);
  });
}
