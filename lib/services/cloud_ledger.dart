import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/ledger.dart';

String get _uid {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Sign in before reading the ledger.');
  }
  return user.uid;
}

/// users/{uid}/events — one document per money movement.
CollectionReference<Map<String, dynamic>> myEvents() => FirebaseFirestore.instance
    .collection('users')
    .doc(_uid)
    .collection('events');

/// users/{uid}/goals — one document per savings goal.
CollectionReference<Map<String, dynamic>> myGoals() => FirebaseFirestore.instance
    .collection('users')
    .doc(_uid)
    .collection('goals');

/// Opening balances and budgets. Totals are calculated, never stored.
DocumentReference<Map<String, dynamic>> mySettings() => FirebaseFirestore.instance
    .collection('users')
    .doc(_uid)
    .collection('settings')
    .doc('ledger');

Map<String, dynamic> eventToMap(MoneyEvent event) => {
      'kind': event.kind,
      'account': event.account,
      'amount': event.amount,
      'category': event.category,
      'person': event.person,
      'note': event.note,
      'date': Timestamp.fromDate(event.date),
    };

MoneyEvent eventFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return MoneyEvent(
    id: doc.id,
    kind: data['kind'] as String,
    account: data['account'] as String,
    amount: (data['amount'] as num).toInt(),
    date: _asDate(data['date']),
    category: data['category'] as String? ?? '',
    person: data['person'] as String? ?? '',
    note: data['note'] as String? ?? '',
  );
}

SavingsGoal goalFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return SavingsGoal(
    id: doc.id,
    name: data['name'] as String,
    target: (data['target'] as num).toInt(),
    saved: (data['saved'] as num?)?.toInt() ?? 0,
  );
}

DateTime _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}

Map<String, int> _intMap(dynamic value) =>
    (value as Map<String, dynamic>).map((key, amount) => MapEntry(key, (amount as num).toInt()));

/// Sample ledger, written once for a brand-new account.
/// Login and the live listener can both call this; the transaction keeps one copy.
Future<void> addSampleLedger() async {
  final settings = mySettings();
  final now = DateTime.now();
  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final existing = await transaction.get(settings);
    if (existing.exists) return;
    transaction.set(settings, {
      'opening': {'Cash': 18000, 'MoMo': 57000, 'Bank': 110000},
      'budgets': {
        'Food': 50000,
        'Transport': 30000,
        'Snacks': 20000,
        'Internet': 15000,
        'Shopping': 40000,
        'Other': 20000,
      },
    });
    transaction.set(
      myEvents().doc(),
      eventToMap(MoneyEvent(
        id: '',
        kind: 'expense',
        account: 'Cash',
        amount: 1200,
        category: 'Transport',
        note: 'Bus fare',
        date: now.subtract(const Duration(hours: 5)),
      )),
    );
    transaction.set(
      myEvents().doc(),
      eventToMap(MoneyEvent(
        id: '',
        kind: 'income',
        account: 'MoMo',
        amount: 10000,
        note: 'Allowance',
        date: now.subtract(const Duration(hours: 1)),
      )),
    );
  });
}

/// Listens to this user's events, goals and settings, and rebuilds the ledger.
Stream<MoneyLedger> watchLedger() {
  final uid = _uid;
  final db = FirebaseFirestore.instance;
  final user = db.collection('users').doc(uid);
  final controller = StreamController<MoneyLedger>();
  QuerySnapshot<Map<String, dynamic>>? eventsSnap;
  QuerySnapshot<Map<String, dynamic>>? goalsSnap;
  DocumentSnapshot<Map<String, dynamic>>? settingsSnap;

  void emit() {
    if (controller.isClosed) return;
    if (eventsSnap == null || goalsSnap == null || settingsSnap == null || !settingsSnap!.exists) {
      return;
    }
    try {
      final data = settingsSnap!.data()!;
      final events = eventsSnap!.docs.map(eventFromDoc).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      controller.add(MoneyLedger(
        opening: _intMap(data['opening']),
        events: events,
        goals: goalsSnap!.docs.map(goalFromDoc).toList(),
        budgets: _intMap(data['budgets']),
      ));
    } catch (e, stack) {
      controller.addError(e, stack);
    }
  }

  final subscriptions = <StreamSubscription<dynamic>>[
    user.collection('events').orderBy('date').snapshots().listen(
          (snap) {
            eventsSnap = snap;
            emit();
          },
          onError: controller.addError,
        ),
    user.collection('goals').snapshots().listen(
          (snap) {
            goalsSnap = snap;
            emit();
          },
          onError: controller.addError,
        ),
    user.collection('settings').doc('ledger').snapshots().listen(
          (snap) {
            settingsSnap = snap;
            emit();
          },
          onError: controller.addError,
        ),
  ];
  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };
  return controller.stream;
}

/// Seeds a new account once, then keeps the screen live.
Stream<MoneyLedger> openLedger() async* {
  await addSampleLedger();
  yield* watchLedger();
}

MoneyLedger _trial(MoneyLedger ledger) => MoneyLedger.decode(ledger.encode());

Future<void> addEvent(MoneyLedger ledger, String kind, String account, int amount,
    {String category = '', String person = '', String note = ''}) async {
  final trial = _trial(ledger);
  trial.add(kind, account, amount, category: category, person: person, note: note);
  await myEvents().add(eventToMap(trial.events.last));
}

Future<void> updateEvent(MoneyLedger ledger, String id,
    {required String kind, required String account, required int amount,
    String category = '', String person = '', String note = ''}) async {
  final trial = _trial(ledger);
  trial.replace(id, kind: kind, account: account, amount: amount,
      category: category, person: person, note: note);
  final updated = trial.events.firstWhere((event) => event.id == id);
  await myEvents().doc(id).update(eventToMap(updated));
}

Future<void> deleteEvent(MoneyLedger ledger, String id) async {
  final trial = _trial(ledger);
  trial.delete(id);
  await myEvents().doc(id).delete();
}

Future<void> createGoalCloud(MoneyLedger ledger, String name, int target) async {
  final trial = _trial(ledger);
  trial.createGoal(name, target);
  final goal = trial.goals.last;
  await myGoals().add({'name': goal.name, 'target': goal.target, 'saved': goal.saved});
}

Future<void> saveGoalCloud(MoneyLedger ledger, String id, int amount) async {
  final trial = _trial(ledger);
  trial.saveForGoal(id, amount);
  final saved = trial.goals.firstWhere((goal) => goal.id == id).saved;
  await myGoals().doc(id).update({'saved': saved});
}

Future<void> setBudgetCloud(MoneyLedger ledger, String category, int amount) async {
  final trial = _trial(ledger);
  trial.setBudget(category, amount);
  await mySettings().set({'budgets': trial.budgets}, SetOptions(merge: true));
}
