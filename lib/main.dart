import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'models/ledger.dart';
import 'services/cloud_ledger.dart';
import 'services/weather.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    runApp(const MyMoneyApp(preview: true));
    return;
  }
  try {
    await Firebase.initializeApp();
  } catch (e) {
    runApp(FirebaseSetupApp(message: '$e'));
    return;
  }
  runApp(const MyMoneyApp());
}

class FirebaseSetupApp extends StatelessWidget {
  const FirebaseSetupApp({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(
          'MyMoney could not reach Firebase.\n\n'
          'Put google-services.json in android/app/ (package name com.example.mymoney), '
          'then stop the app and run it again.\n\n$message',
          textAlign: TextAlign.center,
        )),
      ),
    ),
  );
}

class Palette {
  static const primary = Color(0xFF167D68), background = Color(0xFFF8FAF7),
      accent = Color(0xFFD9A65B), secondary = Color(0xFFD8EDE5), ink = Color(0xFF183C35),
      income = Color(0xFF22946F), expense = Color(0xFFCB6262), muted = Color(0xFF708078);
}
String money(int value) {
  final s = value.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '${value < 0 ? '−' : ''}$s RWF';
}

class MyMoneyApp extends StatelessWidget {
  const MyMoneyApp({super.key, this.preview = false});
  final bool preview;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'MyMoney',
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: Palette.background,
      colorScheme: ColorScheme.fromSeed(seedColor: Palette.primary, primary: Palette.primary,
        surface: Colors.white),
      appBarTheme: const AppBarTheme(backgroundColor: Palette.background, foregroundColor: Palette.ink),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)))),
    home: preview ? const FinanceShell(preview: true) : const AuthGate(home: FinanceShell()));
}

class FinanceShell extends StatefulWidget {
  const FinanceShell({super.key, this.preview = false});
  final bool preview;
  @override
  State<FinanceShell> createState() => _FinanceShellState();
}
class _FinanceShellState extends State<FinanceShell> {
  int index = 0;
  late final Stream<MoneyLedger> _ledgerStream = openLedger();
  late MoneyLedger _local = _sampleLedger();

  static MoneyLedger _sampleLedger() {
    final ledger = MoneyLedger(opening: {'Cash': 18000, 'MoMo': 57000, 'Bank': 110000});
    ledger.add('expense', 'Cash', 1200, category: 'Transport', note: 'Bus fare');
    ledger.add('income', 'MoMo', 10000, note: 'Allowance');
    return ledger;
  }

  Future<bool> _change(void Function() action, {String? success}) async {
    try {
      setState(action);
      if (success != null) _message(success);
      return true;
    } on LedgerException catch (e) {
      _message(e.message);
    } catch (e) {
      _message('Could not save this change: $e');
    }
    return false;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _run(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null) _message(success);
      return true;
    } on LedgerException catch (e) {
      _message(e.message);
    } catch (e) {
      _message('Could not save this change: $e');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preview) return _shell(_local, preview: true);
    return StreamBuilder<MoneyLedger>(
      stream: _ledgerStream,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return Scaffold(
            appBar: _bar(),
            body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
              'Could not load your ledger.\n${snapshot.error}', textAlign: TextAlign.center))),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(appBar: _bar(), body: const Center(child: CircularProgressIndicator()));
        }
        return _shell(snapshot.data!);
      },
    );
  }

  Widget _shell(MoneyLedger ledger, {bool preview = false}) {
    final pages = [
      HomePage(ledger: ledger, onNavigate: (i) => setState(() => index = i)),
      ActivityPage(
        ledger: ledger,
        delete: (id) => preview
            ? _change(() => _local.delete(id), success: 'Transaction deleted')
            : _run(() => deleteEvent(ledger, id), success: 'Transaction deleted'),
        edit: (id, kind, account, amount, category, person, note) => preview
            ? _change(() => _local.replace(id, kind: kind, account: account, amount: amount,
                category: category, person: person, note: note), success: 'Transaction updated')
            : _run(() => updateEvent(ledger, id, kind: kind, account: account, amount: amount,
                category: category, person: person, note: note), success: 'Transaction updated'),
      ),
      AddPage(ledger: ledger, submit: (kind, account, amount, category, person, note) => preview
          ? _change(() => _local.add(kind, account, amount, category: category, person: person, note: note),
              success: 'Transaction recorded')
          : _run(() => addEvent(ledger, kind, account, amount, category: category, person: person, note: note),
              success: 'Transaction recorded')),
      GoalsPage(
        ledger: ledger,
        createGoal: (name, target) => preview
            ? _change(() => _local.createGoal(name, target), success: 'Goal added')
            : _run(() => createGoalCloud(ledger, name, target), success: 'Goal added'),
        saveGoal: (id, amount) => preview
            ? _change(() => _local.saveForGoal(id, amount), success: 'Savings reserved')
            : _run(() => saveGoalCloud(ledger, id, amount), success: 'Savings reserved'),
        setBudget: (category, amount) => preview
            ? _change(() => _local.setBudget(category, amount), success: 'Budget updated')
            : _run(() => setBudgetCloud(ledger, category, amount), success: 'Budget updated'),
      ),
      InsightsPage(ledger: ledger),
    ];
    return Scaffold(
      appBar: _bar(preview: preview),
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i),
        backgroundColor: Colors.white, indicatorColor: Palette.secondary, destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'Goals'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Insights'),
        ]),
    );
  }

  AppBar _bar({bool preview = false}) => AppBar(
    title: Text(preview ? 'MyMoney · browser preview' : 'MyMoney',
        style: const TextStyle(fontWeight: FontWeight.w800, color: Palette.ink)),
    actions: [
      IconButton(tooltip: 'Kigali weather', icon: const Icon(Icons.cloud_outlined), onPressed: () =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const WeatherPage()))),
      if (!preview) IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Log out',
        onPressed: () => FirebaseAuth.instance.signOut(),
      ),
    ],
  );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)), child: child);
}
class Heading extends StatelessWidget {
  const Heading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Palette.ink)),
    if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Palette.muted)),
  ]);
}
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.ledger, required this.onNavigate});
  final MoneyLedger ledger;
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now(); final month = DateTime(now.year, now.month);
    final recent = ledger.events.reversed.take(4).toList();
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Heading('Good evening 👋', subtitle: 'Your money, your plan, your future.'),
      const SizedBox(height: 18),
      Panel(color: Palette.primary, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Available to spend', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Text(money(ledger.available), style: const TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Text('Accounts: ${money(ledger.totalBalance)}', style: const TextStyle(color: Colors.white)),
        Text('Held for others: ${money(ledger.heldTotal)}', style: const TextStyle(color: Colors.white)),
        Text('Reserved savings: ${money(ledger.reserved)}', style: const TextStyle(color: Colors.white)),
      ])),
      const SizedBox(height: 14),
      Row(children: [Expanded(child: Panel(child: _stat('Income this month', money(ledger.totalFor('income', start: month)), Palette.income))),
        const SizedBox(width: 10), Expanded(child: Panel(child: _stat('Expenses this month', money(ledger.totalFor('expense', start: month)), Palette.expense)))]),
      const SizedBox(height: 22),
      const Text('Your accounts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      const SizedBox(height: 8),
      ...ledger.opening.keys.map((a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Panel(child:
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a), Text(money(ledger.balance(a)), style: const TextStyle(fontWeight: FontWeight.w700))])))),
      const SizedBox(height: 12),
      if (ledger.owedPeople.isNotEmpty) ...[
        const Text('Money you are holding', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ...ledger.owedPeople.entries.map((e) => ListTile(title: Text(e.key), trailing: Text(money(e.value)))),
      ],
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        TextButton(onPressed: () => onNavigate(1), child: const Text('See all')),
      ]),
      if (recent.isEmpty) const Panel(child: Text('Nothing recorded yet. Your money story starts with one entry.')),
      ...recent.map((e) => EventTile(event: e)),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: () => onNavigate(2), icon: const Icon(Icons.add), label: const Text('Record money movement')),
    ]);
  }
  Widget _stat(String label, String amount, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)), const SizedBox(height: 8),
    Text(amount, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16))]);
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.onDelete, this.onEdit});
  final MoneyEvent event;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final positive = event.kind == 'income' || event.kind == 'hold';
    final title = event.kind == 'hold' ? 'Held for ${event.person}' : event.kind == 'return'
      ? 'Returned to ${event.person}' : event.note.isNotEmpty ? event.note : event.kind == 'income' ? 'Income' : event.category;
    return Card(child: ListTile(
      onTap: onEdit,
      leading: CircleAvatar(backgroundColor: Palette.secondary,
        child: Icon(positive ? Icons.south_west : Icons.north_east, color: Palette.primary)),
      title: Text(title), subtitle: Text('${event.account} · ${event.kind} · ${event.date.day}/${event.date.month}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${positive ? '+' : '−'}${money(event.amount)}', style: TextStyle(fontWeight: FontWeight.w700,
          color: positive ? Palette.income : Palette.expense)),
        if (onDelete != null) IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: onDelete,
        ),
      ])));
  }
}

typedef EditEvent = Future<bool> Function(String id, String kind, String account, int amount, String category, String person, String note);
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.ledger, required this.delete, required this.edit});
  final MoneyLedger ledger;
  final Future<bool> Function(String id) delete;
  final EditEvent edit;
  @override State<ActivityPage> createState() => _ActivityPageState();
}
class _ActivityPageState extends State<ActivityPage> {
  String filter = 'All', query = '';
  @override Widget build(BuildContext context) {
    final data = widget.ledger.events.reversed.where((e) =>
      (filter == 'All' || e.kind == filter.toLowerCase()) &&
      ('${e.kind} ${e.person} ${e.category} ${e.account} ${e.note}'.toLowerCase()).contains(query.toLowerCase())).toList();
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Heading('Activity', subtitle: 'Tap an entry to edit it.'), const SizedBox(height: 12),
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search transactions'),
        onChanged: (v) => setState(() => query = v)), const SizedBox(height: 10),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ['All', 'Income', 'Expense', 'Hold', 'Return']
        .map((x) => Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(x),
          selected: filter == x, onSelected: (_) => setState(() => filter = x)))).toList())),
      const SizedBox(height: 12),
      if (data.isEmpty) const Panel(child: Text('No matching transactions yet.')),
      ...data.map((e) => EventTile(
        event: e,
        onEdit: () {
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Edit transaction')),
            body: AddPage(
              ledger: widget.ledger,
              existing: e,
              submit: (kind, account, amount, category, person, note) =>
                  widget.edit(e.id, kind, account, amount, category, person, note),
            ),
          )));
        },
        onDelete: () async {
          final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Delete this entry?'),
            content: const Text('This changes your balances and reports. This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ));
          if (ok == true) widget.delete(e.id);
        },
      )),
    ]);
  }
}

typedef SubmitEvent = Future<bool> Function(String kind, String account, int amount, String category, String person, String note);
class AddPage extends StatefulWidget {
  const AddPage({super.key, required this.ledger, required this.submit, this.existing});
  final MoneyLedger ledger;
  final SubmitEvent submit;
  final MoneyEvent? existing;
  @override State<AddPage> createState() => _AddPageState();
}
class _AddPageState extends State<AddPage> {
  String kind = 'expense', account = 'Cash', category = 'Food';
  final amount = TextEditingController(), person = TextEditingController(), note = TextEditingController();
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    kind = existing.kind;
    account = widget.ledger.opening.containsKey(existing.account) ? existing.account : widget.ledger.opening.keys.first;
    category = MoneyLedger.categories.contains(existing.category) ? existing.category : MoneyLedger.categories.first;
    amount.text = '${existing.amount}';
    person.text = existing.person;
    note.text = existing.note;
  }
  @override void dispose() { amount.dispose(); person.dispose(); note.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Heading(widget.existing == null ? 'Add transaction' : 'Edit transaction',
      subtitle: widget.existing == null ? 'Make every franc count.' : 'Correct this entry. Balances update live.'),
    const SizedBox(height: 14),
    DropdownButtonFormField<String>(initialValue: kind, decoration: const InputDecoration(labelText: 'Movement type'),
      items: const ['expense', 'income', 'hold', 'return'].map((x) => DropdownMenuItem(value: x, child: Text(x.toUpperCase()))).toList(),
      onChanged: (v) => setState(() => kind = v!)), const SizedBox(height: 12),
    DropdownButtonFormField<String>(initialValue: account, decoration: const InputDecoration(labelText: 'Account'),
      items: widget.ledger.opening.keys.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
      onChanged: (v) => setState(() => account = v!)), const SizedBox(height: 12),
    TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (RWF)')),
    const SizedBox(height: 12),
    if (kind == 'expense') ...[DropdownButtonFormField<String>(initialValue: category,
      decoration: const InputDecoration(labelText: 'Category'),
      items: MoneyLedger.categories.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
      onChanged: (v) => setState(() => category = v!)), const SizedBox(height: 12)],
    if (kind == 'hold' || kind == 'return') ...[TextField(controller: person,
      decoration: const InputDecoration(labelText: 'Whose money? (name)')), const SizedBox(height: 12)],
    TextField(controller: note, decoration: const InputDecoration(labelText: 'Description (optional)')),
    const SizedBox(height: 18),
    FilledButton.icon(onPressed: () async {
      final value = int.tryParse(amount.text.trim());
      if (value == null || value <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a whole number greater than zero')));
        return;
      }
      final saved = await widget.submit(kind, account, value, category, person.text.trim(), note.text.trim());
      if (saved && widget.existing != null && context.mounted) Navigator.pop(context);
    }, icon: const Icon(Icons.check_circle_outline),
      label: Text(widget.existing == null ? 'Record transaction' : 'Save changes')),
    const SizedBox(height: 12),
    const Panel(color: Palette.secondary, child: Text('Money received for someone else is never counted as your personal income. Return it using the Return type.')),
  ]);
}

typedef GoalCreate = Future<bool> Function(String name, int target);
typedef GoalSave = Future<bool> Function(String id, int amount);
typedef BudgetSet = Future<bool> Function(String category, int amount);
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.ledger, required this.createGoal, required this.saveGoal, required this.setBudget});
  final MoneyLedger ledger;
  final GoalCreate createGoal;
  final GoalSave saveGoal;
  final BudgetSet setBudget;
  Future<void> _input(BuildContext context, String heading, Future<bool> Function(String, int) onDone, {String? initial}) async {
    final name = TextEditingController(text: initial ?? ''); final amount = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(heading), content:
      Column(mainAxisSize: MainAxisSize.min, children: [if (initial == null) TextField(controller: name,
        decoration: const InputDecoration(labelText: 'Goal name')),
        TextField(controller: amount, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (RWF)'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))]));
    if (result == true) {
      final value = int.tryParse(amount.text.trim());
      if (value == null || value <= 0) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a positive whole amount')));
      } else { onDone(initial ?? name.text, value); }
    }
    name.dispose(); amount.dispose();
  }
  @override Widget build(BuildContext context) {
    final now = DateTime.now(), month = DateTime(now.year, now.month);
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Heading('Goals & budgets', subtitle: 'A little plan makes a big difference.'),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Savings goals',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), IconButton(icon: const Icon(Icons.add_circle_outline),
        onPressed: () => _input(context, 'Create savings goal', createGoal))]),
      if (ledger.goals.isEmpty) const Panel(child: Text('No savings goals yet. Create one to get started.')),
      ...ledger.goals.map((g) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), const SizedBox(height: 8),
          Text('${money(g.saved)} of ${money(g.target)}'), const SizedBox(height: 8),
          LinearProgressIndicator(value: g.saved/g.target, minHeight: 9, borderRadius: BorderRadius.circular(10)),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _input(context,
            'Save toward ${g.name}', (_, amount) => saveGoal(g.id, amount), initial: g.name),
            icon: const Icon(Icons.add), label: const Text('Add savings'))),
        ])))),
      const SizedBox(height: 20),
      const Text('Monthly spending budgets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ...ledger.budgets.entries.map((b) {
        final used = ledger.totalFor('expense', start: month, category: b.key);
        final ratio = used / b.value;
        return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Panel(child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(b.key, style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(tooltip: 'Edit budget', icon: const Icon(Icons.edit_outlined), onPressed: () =>
              _input(context, 'Budget for ${b.key}', (_, amount) => setBudget(b.key, amount), initial: b.key))]),
          Align(alignment: Alignment.centerLeft, child: Text('${money(used)} / ${money(b.value)}',
            style: const TextStyle(color: Palette.muted))), const SizedBox(height: 8),
          LinearProgressIndicator(value: ratio.clamp(0.0, 1.0), minHeight: 9,
            color: ratio >= 0.8 ? Palette.accent : Palette.primary, borderRadius: BorderRadius.circular(10)),
          if (ratio >= 1) const Align(alignment: Alignment.centerLeft, child: Text('Budget limit reached',
            style: TextStyle(color: Palette.expense))),
        ])));
      }),
    ]);
  }
}

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key, required this.ledger});
  final MoneyLedger ledger;
  @override State<InsightsPage> createState() => _InsightsPageState();
}
class _InsightsPageState extends State<InsightsPage> {
  String range = 'Month';
  @override Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = range == 'Day' ? DateTime(now.year, now.month, now.day) : range == 'Week'
      ? DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1)) : DateTime(now.year, now.month);
    final income = widget.ledger.totalFor('income', start: start);
    final expense = widget.ledger.totalFor('expense', start: start);
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Heading('Insights', subtitle: 'Your numbers, made clearer.'), const SizedBox(height: 14),
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'Day', label: Text('Day')),
        ButtonSegment(value: 'Week', label: Text('Week')), ButtonSegment(value: 'Month', label: Text('Month'))],
        selected: {range}, onSelectionChanged: (v) => setState(() => range = v.first)),
      const SizedBox(height: 14), Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Personal income: ${money(income)}'), const SizedBox(height: 9),
        Text('Expenses: ${money(expense)}'), const Divider(height: 28),
        Text('Net: ${money(income - expense)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ])), const SizedBox(height: 20),
      const Text('Spending by category', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ...MoneyLedger.categories.map((c) {
        final used = widget.ledger.totalFor('expense', start: start, category: c);
        if (used == 0) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$c   ${money(used)}'), const SizedBox(height: 5),
          LinearProgressIndicator(value: expense == 0 ? 0 : used / expense, minHeight: 9,
            borderRadius: BorderRadius.circular(10)),
        ]));
      }),
      if (expense == 0) const Panel(child: Text('No spending recorded in this period.')),
    ]);
  }
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});
  @override State<WeatherPage> createState() => _WeatherPageState();
}
class _WeatherPageState extends State<WeatherPage> {
  final service = WeatherService();
  KigaliWeather? data;
  String? error;
  bool loading = true;
  @override void initState() { super.initState(); _fetch(); }
  Future<void> _fetch() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await service.fetch();
      if (mounted) setState(() => data = result);
    } catch (_) {
      if (mounted) setState(() { error = 'Could not load Kigali weather. Check your internet connection.'; data = null; });
    } finally { if (mounted) setState(() => loading = false); }
  }
  @override void dispose() { service.close(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Live Kigali weather')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: loading
      ? const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Loading live weather…')])
      : error != null ? Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, size: 56, color: Palette.expense), const SizedBox(height: 14),
        Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12),
        FilledButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]) : Panel(color: Palette.secondary, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wb_sunny_outlined, color: Palette.primary, size: 52), const SizedBox(height: 12),
        Text('${data!.temperature.toStringAsFixed(1)}°C', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
        Text('Wind: ${data!.wind.toStringAsFixed(1)} km/h'), const SizedBox(height: 10),
        const Text('Live data: Open-Meteo · Kigali'), TextButton.icon(onPressed: _fetch,
          icon: const Icon(Icons.refresh), label: const Text('Refresh')),
      ])))));
}
