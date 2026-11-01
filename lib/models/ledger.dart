import 'dart:convert';

/// Cash amounts are integer RWF. Every movement is an immutable ledger event.
class MoneyEvent {
  MoneyEvent({required this.id, required this.kind, required this.account,
    required this.amount, required this.date, this.category = '', this.person = '', this.note = ''});
  final String id, kind, account, category, person, note;
  final int amount;
  final DateTime date;
  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'account': account,
    'amount': amount, 'date': date.toIso8601String(), 'category': category,
    'person': person, 'note': note};
  factory MoneyEvent.fromJson(Map<String, dynamic> x) => MoneyEvent(
    id: x['id'] as String, kind: x['kind'] as String, account: x['account'] as String,
    amount: (x['amount'] as num).toInt(), date: DateTime.parse(x['date'] as String),
    category: x['category'] as String? ?? '', person: x['person'] as String? ?? '',
    note: x['note'] as String? ?? '');
}

class SavingsGoal {
  SavingsGoal({required this.id, required this.name, required this.target, this.saved = 0});
  final String id;
  String name;
  int target, saved;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'target': target, 'saved': saved};
  factory SavingsGoal.fromJson(Map<String, dynamic> x) => SavingsGoal(id: x['id'] as String,
    name: x['name'] as String, target: (x['target'] as num).toInt(), saved: (x['saved'] as num).toInt());
}

class LedgerException implements Exception {
  LedgerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Every command is checked fully before state changes.
class MoneyLedger {
  MoneyLedger({Map<String, int>? opening, List<MoneyEvent>? events,
    List<SavingsGoal>? goals, Map<String, int>? budgets})
      : opening = Map.of(opening ?? {'Cash': 0, 'MoMo': 0, 'Bank': 0}),
        events = List.of(events ?? []), goals = List.of(goals ?? []),
        budgets = Map.of(budgets ?? {'Food': 50000, 'Transport': 30000,
          'Snacks': 20000, 'Internet': 15000, 'Shopping': 40000, 'Other': 20000});

  final Map<String, int> opening;
  final List<MoneyEvent> events;
  final List<SavingsGoal> goals;
  final Map<String, int> budgets;
  int _counter = 0;
  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
  static const categories = ['Food', 'Transport', 'Snacks', 'Internet', 'Shopping', 'Education', 'Bills', 'Health', 'Other'];

  int balance(String account) {
    _account(account);
    var value = opening[account]!;
    for (final e in events.where((e) => e.account == account)) {
      if (e.kind == 'income' || e.kind == 'hold') value += e.amount;
      if (e.kind == 'expense' || e.kind == 'return') value -= e.amount;
    }
    return value;
  }
  int held(String person, {String? account}) {
    var result = 0;
    for (final e in events) {
      if (e.person.toLowerCase() == person.toLowerCase() && (account == null || e.account == account)) {
        if (e.kind == 'hold') result += e.amount;
        if (e.kind == 'return') result -= e.amount;
      }
    }
    return result;
  }
  int heldIn(String account) {
    var total = 0;
    for (final e in events.where((e) => e.account == account)) {
      if (e.kind == 'hold') total += e.amount;
      if (e.kind == 'return') total -= e.amount;
    }
    return total;
  }
  int get heldTotal => opening.keys.fold(0, (v, account) => v + heldIn(account));
  int get reserved => goals.fold(0, (v, g) => v + g.saved);
  int get totalBalance => opening.keys.fold(0, (v, account) => v + balance(account));
  int get available => totalBalance - heldTotal - reserved;
  int spendableIn(String account) => balance(account) - heldIn(account);
  int totalFor(String kind, {DateTime? start, DateTime? end, String? category}) => events
    .where((e) => e.kind == kind && (category == null || e.category == category) &&
      (start == null || !e.date.isBefore(start)) && (end == null || e.date.isBefore(end)))
    .fold(0, (int s, e) => s + e.amount);
  Map<String, int> get owedPeople {
    final m = <String, int>{};
    for (final e in events.where((e) => e.kind == 'hold' || e.kind == 'return')) {
      m[e.person] = (m[e.person] ?? 0) + (e.kind == 'hold' ? e.amount : -e.amount);
    }
    m.removeWhere((k, v) => v == 0);
    return m;
  }
  void _account(String name) { if (!opening.containsKey(name)) throw LedgerException('Unknown account: $name'); }
  void _valid(int amount) { if (amount <= 0) throw LedgerException('Amount must be greater than zero'); }
  void _personal(String account, int amount) {
    if (spendableIn(account) < amount || available < amount) {
      throw LedgerException('Insufficient personal balance in $account');
    }
  }
  void add(String kind, String account, int amount, {String category = '', String person = '', String note = '', DateTime? date}) {
    events.add(_makeEvent(kind, account, amount, category: category, person: person, note: note, date: date, id: _id()));
  }

  /// Replaces one entry, then refuses the change if any later balance would go invalid.
  void replace(String id, {required String kind, required String account, required int amount,
      String category = '', String person = '', String note = '', DateTime? date}) {
    final index = events.indexWhere((e) => e.id == id);
    if (index < 0) throw LedgerException('Transaction not found');
    final old = events.removeAt(index);
    try {
      final event = _makeEvent(kind, account, amount, category: category, person: person,
          note: note, date: date ?? old.date, id: id);
      events.insert(index, event);
      if (!_historyValid()) {
        throw LedgerException('This change would make an account or held-money balance invalid');
      }
    } catch (e) {
      events.removeWhere((event) => event.id == id);
      events.insert(index, old);
      if (e is LedgerException) rethrow;
      throw LedgerException('$e');
    }
  }

  MoneyEvent _makeEvent(String kind, String account, int amount,
      {String category = '', String person = '', String note = '', DateTime? date, required String id}) {
    _account(account); _valid(amount);
    if (kind == 'expense') {
      if (category.trim().isEmpty) throw LedgerException('Select a category');
      _personal(account, amount);
    } else if (kind == 'return') {
      if (person.trim().isEmpty) throw LedgerException('Enter the owner name');
      if (held(person, account: account) < amount) throw LedgerException('Cannot return more than owed to $person in $account');
      if (balance(account) < amount) throw LedgerException('Insufficient balance in $account');
    } else if (kind == 'hold') {
      if (person.trim().isEmpty) throw LedgerException('Enter the owner name');
    } else if (kind != 'income') {
      throw LedgerException('Unknown transaction type');
    }
    return MoneyEvent(id: id, kind: kind, account: account, amount: amount,
      category: category.trim(), person: person.trim(), note: note.trim(), date: date ?? DateTime.now());
  }
  void delete(String id) {
    final index = events.indexWhere((e) => e.id == id);
    if (index < 0) throw LedgerException('Transaction not found');
    final removed = events.removeAt(index);
    // Refuse deletion if any chronological replay would invalidate ownership or balances.
    if (!_historyValid()) {
      events.insert(index, removed);
      throw LedgerException('Deletion would make an account or held-money balance invalid');
    }
  }
  bool _historyValid() {
    final accounts = Map.of(opening);
    final owed = <String, int>{};
    final sorted = List<MoneyEvent>.of(events)..sort((a,b) => a.date.compareTo(b.date));
    for (final e in sorted) {
      if (e.kind == 'income' || e.kind == 'hold') accounts[e.account] = accounts[e.account]! + e.amount;
      if (e.kind == 'expense' || e.kind == 'return') accounts[e.account] = accounts[e.account]! - e.amount;
      if (e.kind == 'hold' || e.kind == 'return') {
        final key = '${e.account}|${e.person.toLowerCase()}';
        owed[key] = (owed[key] ?? 0) + (e.kind == 'hold' ? e.amount : -e.amount);
        if (owed[key]! < 0) return false;
      }
      if (accounts[e.account]! < 0) return false;
      final heldAccount = owed.entries.where((x) => x.key.startsWith('${e.account}|')).fold<int>(0, (s, x) => s + x.value);
      if (accounts[e.account]! < heldAccount) return false;
    }
    return totalBalance - heldTotal >= reserved;
  }
  void createGoal(String name, int target) {
    if (name.trim().isEmpty || target <= 0) throw LedgerException('Enter a goal name and positive target');
    goals.add(SavingsGoal(id: _id(), name: name.trim(), target: target));
  }
  void saveForGoal(String id, int amount) {
    _valid(amount);
    final g = goals.firstWhere((g) => g.id == id, orElse: () => throw LedgerException('Goal not found'));
    if (amount > available) throw LedgerException('Insufficient available money for savings');
    if (g.saved + amount > g.target) throw LedgerException('Amount exceeds goal target');
    g.saved += amount;
  }
  void setBudget(String category, int amount) {
    if (category.trim().isEmpty || amount <= 0) throw LedgerException('Budget must be positive');
    budgets[category] = amount;
  }
  Map<String, dynamic> toJson() => {'opening': opening, 'events': events.map((e) => e.toJson()).toList(),
    'goals': goals.map((g) => g.toJson()).toList(), 'budgets': budgets};
  String encode() => jsonEncode(toJson());
  factory MoneyLedger.decode(String data) {
    final json = jsonDecode(data) as Map<String, dynamic>;
    return MoneyLedger(opening: (json['opening'] as Map<String,dynamic>).map((k,v) => MapEntry(k,(v as num).toInt())),
      events: (json['events'] as List).map((e) => MoneyEvent.fromJson(Map<String,dynamic>.from(e as Map))).toList(),
      goals: (json['goals'] as List).map((e) => SavingsGoal.fromJson(Map<String,dynamic>.from(e as Map))).toList(),
      budgets: (json['budgets'] as Map<String,dynamic>).map((k,v) => MapEntry(k,(v as num).toInt())));
  }
}
