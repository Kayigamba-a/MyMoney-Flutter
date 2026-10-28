import '../models/ledger.dart';

/// The original 5-event Lab 12 command processor. All rules run in MoneyLedger.
class Lab12Brain {
  final ledger = MoneyLedger(opening: {'Cash': 0, 'MoMo': 0, 'Bank': 0});
  String handle(String command) {
    final p = command.split(':');
    final kind = p[0].toLowerCase();
    if (!['income', 'expense', 'hold', 'return', 'summary'].contains(kind)) return 'Unknown command: $command';
    if (kind == 'summary') {
      if (p.length != 1) return 'Refused: Wrong number of fields';
      return 'Summary: Cash ${ledger.balance('Cash')}, MoMo ${ledger.balance('MoMo')}, Bank ${ledger.balance('Bank')} RWF';
    }
    final lengths = {'income': 3, 'expense': 4, 'hold': 4, 'return': 4};
    if (p.length != lengths[kind]) return 'Refused: Wrong number of fields';
    final account = {'cash': 'Cash', 'momo': 'MoMo', 'bank': 'Bank'}[p[1].toLowerCase()] ?? p[1];
    final amount = int.tryParse(p.last);
    if (amount == null) return 'Refused: Amount must be a whole number';
    try {
      if (kind == 'income') {
        ledger.add('income', account, amount);
        return 'Received $amount RWF in $account';
      }
      if (kind == 'expense') {
        ledger.add('expense', account, amount, category: p[2]);
        return 'Spent $amount RWF on ${p[2]} from $account';
      }
      if (kind == 'hold') {
        ledger.add('hold', account, amount, person: p[2]);
        return 'Holding $amount RWF for ${p[2]} in $account';
      }
      ledger.add('return', account, amount, person: p[2]);
      return 'Returned $amount RWF to ${p[2]} from $account';
    } on LedgerException catch (e) {
      return 'Refused: ${e.message}';
    }
  }
}

const lab12Scenario = <String>[
  'income:momo:50000',
  'expense:momo:food:3500',
  'income:cash:10000',
  'hold:bank:Eric:20000',
  'expense:cash:transport:1200',
  'return:bank:Eric:5000',
  'expense:cash:snacks:20000',
  'return:bank:Eric:30000',
  'summary',
  'fly:momo:1000',
];

// EXPECTED OUTPUT — written before executing the scenario:
// Received 50000 RWF in MoMo
// Spent 3500 RWF on food from MoMo
// Received 10000 RWF in Cash
// Holding 20000 RWF for Eric in Bank
// Spent 1200 RWF on transport from Cash
// Returned 5000 RWF to Eric from Bank
// Refused: Insufficient personal balance in Cash
// Refused: Cannot return more than owed to Eric in Bank
// Summary: Cash 8800, MoMo 46500, Bank 15000 RWF
// Unknown command: fly:momo:1000
List<String> runLab12Scenario() {
  final brain = Lab12Brain();
  return lab12Scenario.map(brain.handle).toList();
}
