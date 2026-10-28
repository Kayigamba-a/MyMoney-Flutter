import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/ledger.dart';
import 'services/weather.dart';

void main() => runApp(const MyMoneyApp());

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
  const MyMoneyApp({super.key});
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
    home: const FinanceShell());
}

class FinanceShell extends StatefulWidget {
  const FinanceShell({super.key});
  @override
  State<FinanceShell> createState() => _FinanceShellState();
}
class _FinanceShellState extends State<FinanceShell> {
  MoneyLedger ledger = _starterLedger();
  static MoneyLedger _starterLedger() {
    final l = MoneyLedger(opening: {'Cash': 18000, 'MoMo': 57000, 'Bank': 110000});
    l.add('expense', 'Cash', 1200, category: 'Transport', note: 'Bus fare');
    l.add('income', 'MoMo', 10000, note: 'Allowance');
    return l;
  }
  int index = 0;
  bool ready = false;
  static const key = 'mymoney_ledger_v1';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key);
      if (saved != null) ledger = MoneyLedger.decode(saved);
    } catch (e) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _message('Saved data could not be read: $e'));
    }
    if (mounted) setState(() => ready = true);
  }
  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
  Future<void> _change(void Function() action, {String? success}) async {
    try {
      setState(action);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, ledger.encode());
      if (success != null) _message(success);
    } on LedgerException catch (e) {
      _message(e.message);
    } catch (e) {
      _message('Could not save this change: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(ledger: ledger, onNavigate: (i) => setState(() => index = i)),
      ActivityPage(ledger: ledger, delete: (id) => _change(() => ledger.delete(id), success: 'Transaction deleted')),
      AddPage(ledger: ledger, submit: (kind, account, amount, category, person, note) =>
        _change(() => ledger.add(kind, account, amount, category: category, person: person, note: note),
          success: 'Transaction recorded')),
      GoalsPage(ledger: ledger, createGoal: (name, target) => _change(() => ledger.createGoal(name, target), success: 'Goal added'),
        saveGoal: (id, amount) => _change(() => ledger.saveForGoal(id, amount), success: 'Savings reserved'),
        setBudget: (category, amount) => _change(() => ledger.setBudget(category, amount), success: 'Budget updated')),
      InsightsPage(ledger: ledger),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('MyMoney', style: TextStyle(fontWeight: FontWeight.w800, color: Palette.ink)),
        actions: [IconButton(tooltip: 'Kigali weather', icon: const Icon(Icons.cloud_outlined), onPressed: () =>
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const WeatherPage())))]),
      body: ready ? SafeArea(child: pages[index]) : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i),
        backgroundColor: Colors.white, indicatorColor: Palette.secondary, destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'Goals'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Insights'),
        ]));
  }
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
  const EventTile({super.key, required this.event, this.onDelete});
  final MoneyEvent event;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final positive = event.kind == 'income' || event.kind == 'hold';
    final title = event.kind == 'hold' ? 'Held for ${event.person}' : event.kind == 'return'
      ? 'Returned to ${event.person}' : event.note.isNotEmpty ? event.note : event.kind == 'income' ? 'Income' : event.category;
    return Card(child: ListTile(leading: CircleAvatar(backgroundColor: Palette.secondary,
      child: Icon(positive ? Icons.south_west : Icons.north_east, color: Palette.primary)),
      title: Text(title), subtitle: Text('${event.account} · ${event.kind} · ${event.date.day}/${event.date.month}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${positive ? '+' : '−'}${money(event.amount)}', style: TextStyle(fontWeight: FontWeight.w700,
          color: positive ? Palette.income : Palette.expense)),
        if (onDelete != null) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: onDelete),
      ])));
  }
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.ledger, required this.delete});
  final MoneyLedger ledger;
  final ValueChanged<String> delete;
  @override State<ActivityPage> createState() => _ActivityPageState();
}
class _ActivityPageState extends State<ActivityPage> {
  String filter = 'All', query = '';
  @override Widget build(BuildContext context) {
    final data = widget.ledger.events.reversed.where((e) =>
      (filter == 'All' || e.kind == filter.toLowerCase()) &&
      ('${e.kind} ${e.person} ${e.category} ${e.account} ${e.note}'.toLowerCase()).contains(query.toLowerCase())).toList();
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Heading('Activity', subtitle: 'Every movement has a story.'), const SizedBox(height: 12),
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search transactions'),
        onChanged: (v) => setState(() => query = v)), const SizedBox(height: 10),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ['All', 'Income', 'Expense', 'Hold', 'Return']
        .map((x) => Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(x),
          selected: filter == x, onSelected: (_) => setState(() => filter = x)))).toList())),
      const SizedBox(height: 12),
      if (data.isEmpty) const Panel(child: Text('No matching transactions yet.')),
      ...data.map((e) => EventTile(event: e, onDelete: () async {
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Delete this entry?'), content: const Text('This changes your balances and reports.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
        if (ok == true) widget.delete(e.id);
      })),
    ]);
  }
}

typedef SubmitEvent = void Function(String kind, String account, int amount, String category, String person, String note);
class AddPage extends StatefulWidget {
  const AddPage({super.key, required this.ledger, required this.submit});
  final MoneyLedger ledger;
  final SubmitEvent submit;
  @override State<AddPage> createState() => _AddPageState();
}
class _AddPageState extends State<AddPage> {
  String kind = 'expense', account = 'Cash', category = 'Food';
  final amount = TextEditingController(), person = TextEditingController(), note = TextEditingController();
  @override void dispose() { amount.dispose(); person.dispose(); note.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const Heading('Add transaction', subtitle: 'Make every franc count.'), const SizedBox(height: 14),
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
    FilledButton.icon(onPressed: () {
      final value = int.tryParse(amount.text.trim());
      if (value == null || value <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a whole number greater than zero')));
        return;
      }
      widget.submit(kind, account, value, category, person.text.trim(), note.text.trim());
    }, icon: const Icon(Icons.check_circle_outline), label: const Text('Record transaction')),
    const SizedBox(height: 12),
    const Panel(color: Palette.secondary, child: Text('Money received for someone else is never counted as your personal income. Return it using the Return type.')),
  ]);
}

typedef GoalCreate = void Function(String name, int target);
typedef GoalSave = void Function(String id, int amount);
typedef BudgetSet = void Function(String category, int amount);
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.ledger, required this.createGoal, required this.saveGoal, required this.setBudget});
  final MoneyLedger ledger;
  final GoalCreate createGoal;
  final GoalSave saveGoal;
  final BudgetSet setBudget;
  Future<void> _input(BuildContext context, String heading, void Function(String, int) onDone, {String? initial}) async {
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
