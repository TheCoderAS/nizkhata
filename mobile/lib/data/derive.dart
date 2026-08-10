// Derivation engine — ports src/lib/txn.ts, derive.ts, period.ts and
// financialYear.ts. Everything here is computed from transactions + entities,
// never stored, and matches the web app's formulas exactly.

import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'models.dart';

double roundMoney(num n) => ((n + 1e-9) * 100).round() / 100;

// ---- transaction engine (txn.ts) ------------------------------------------

const _primarySign = <String, int>{
  'income': 1,
  'interest_income': 1,
  'borrow': 1,
  'expense': -1,
  'interest_expense': -1,
  'fee': -1,
  'tax': -1,
  'lend': -1,
  'transfer_out': -1,
  'transfer_in': 0,
  'repayment': 0,
};

/// Signed effect of a line on the primary account. `repayment` needs the debt.
double primaryAccountEffect(TxnLine line, Debt? debt) {
  if (line.external) return 0;
  if (line.type == 'repayment') {
    if (debt == null) return 0;
    return (debt.direction == 'owe' ? -1 : 1) * line.amount;
  }
  return (_primarySign[line.type] ?? 0) * line.amount;
}

/// Net delta per account touched by a transaction (transfer_in credits toAccount).
Map<String, double> accountDeltas(Txn txn, Map<String, Debt> debtsById) {
  final deltas = <String, double>{};
  void add(String acct, double amt) {
    deltas[acct] = roundMoney((deltas[acct] ?? 0) + amt);
  }

  for (final line in txn.lines) {
    if (line.type == 'transfer_in') {
      if (line.toAccountId != null) add(line.toAccountId!, line.amount);
      continue;
    }
    add(txn.accountId, primaryAccountEffect(line, line.debtId != null ? debtsById[line.debtId] : null));
  }
  return deltas;
}

double computeTotal(List<TxnLine> lines, Map<String, Debt> debtsById) {
  var total = 0.0;
  for (final line in lines) {
    total += primaryAccountEffect(line, line.debtId != null ? debtsById[line.debtId] : null);
  }
  return roundMoney(total);
}

// ---- balances --------------------------------------------------------------

Map<String, double> accountBalances(
    List<Account> accounts, List<Txn> txns, Map<String, Debt> debtsById) {
  final balances = <String, double>{};
  for (final a in accounts) {
    balances[a.id] = a.openingBalance;
  }
  for (final txn in txns) {
    accountDeltas(txn, debtsById).forEach((acctId, delta) {
      balances[acctId] = roundMoney((balances[acctId] ?? 0) + delta);
    });
  }
  return balances;
}

// ---- debt outstanding ------------------------------------------------------

double debtOutstanding(Debt debt, List<Txn> txns) {
  final establishing = debt.direction == 'owe' ? 'borrow' : 'lend';
  var total = 0.0;
  for (final txn in txns) {
    for (final line in txn.lines) {
      if (line.debtId != debt.id) continue;
      if (line.type == establishing) {
        total += line.amount;
      } else if (line.type == 'repayment') {
        total -= line.amount;
      }
    }
  }
  return roundMoney(total);
}

// ---- dues ------------------------------------------------------------------

double dueSettledAmount(Due due, List<Txn> txns) {
  var total = 0.0;
  for (final t in txns) {
    if (t.dueId == due.id) total += t.totalAmount.abs();
  }
  return roundMoney(total);
}

/// Status derived from settled amount (mirrors dueStatusFromSettled).
String dueStatusFromSettled(Due due, double settled) {
  if (due.status == 'cancelled') return 'cancelled';
  if (settled <= 0) return 'open';
  if (settled + 0.005 < due.amount) return 'partial';
  return 'settled';
}

// ---- custodial -------------------------------------------------------------

double custodialHeld(List<Debt> debts, List<Txn> txns) {
  var total = 0.0;
  for (final d in debts) {
    if (d.purpose == 'custodial_savings' && d.direction == 'owe') {
      total += debtOutstanding(d, txns);
    }
  }
  return roundMoney(total);
}

// ---- contact position ------------------------------------------------------

class ContactPosition {
  final double net; // >0 they owe you, <0 you owe them
  final double totalIn;
  final double totalOut;
  ContactPosition(this.net, this.totalIn, this.totalOut);
}

ContactPosition contactPosition(String contactId, List<Debt> debts, List<Txn> txns) {
  var net = 0.0;
  for (final debt in debts) {
    if (debt.contactId != contactId) continue;
    final outstanding = debtOutstanding(debt, txns);
    net += debt.direction == 'owed' ? outstanding : -outstanding;
  }
  var totalIn = 0.0;
  var totalOut = 0.0;
  for (final t in txns) {
    if (t.contactId != contactId) continue;
    if (t.totalAmount >= 0) {
      totalIn += t.totalAmount;
    } else {
      totalOut += -t.totalAmount;
    }
  }
  return ContactPosition(roundMoney(net), roundMoney(totalIn), roundMoney(totalOut));
}

// ---- spend by category -----------------------------------------------------

class CategorySpend {
  final String id;
  final String name;
  final double amount;
  CategorySpend(this.id, this.name, this.amount);
}

List<CategorySpend> spendByCategoryInRange(
    List<Txn> txns, List<AppCategory> categories, DateTime start, DateTime end) {
  final byId = {for (final c in categories) c.id: c};
  final sums = <String, double>{};
  for (final t in txns) {
    if (t.date.isBefore(start) || !t.date.isBefore(end)) continue;
    for (final line in t.lines) {
      if (line.type != 'expense') continue;
      if (line.categoryId == null) continue;
      sums[line.categoryId!] = (sums[line.categoryId!] ?? 0) + line.amount;
    }
  }
  final out = <CategorySpend>[];
  sums.forEach((id, amt) {
    out.add(CategorySpend(id, byId[id]?.name ?? 'Uncategorized', roundMoney(amt)));
  });
  out.sort((a, b) => b.amount.compareTo(a.amount));
  return out;
}

// ---- net worth series ------------------------------------------------------

class NetWorthPoint {
  final String label;
  final double netWorth;
  NetWorthPoint(this.label, this.netWorth);
}

List<NetWorthPoint> netWorthSeries(
    List<Account> accounts, List<Debt> debts, List<Txn> txns, DateTime start, DateTime end) {
  final debtsById = {for (final d in debts) d.id: d};
  final sorted = [...txns]..sort((a, b) => a.date.compareTo(b.date));
  final points = <NetWorthPoint>[];
  var accountsTotal = accounts.fold<double>(0, (s, a) => s + a.openingBalance);
  final debtOut = <String, double>{};
  var idx = 0;
  var cursor = DateTime(start.year, start.month, 1);

  while (cursor.isBefore(end)) {
    final cutoff = DateTime(cursor.year, cursor.month + 1, 1);
    while (idx < sorted.length && sorted[idx].date.isBefore(cutoff)) {
      final txn = sorted[idx];
      accountDeltas(txn, debtsById).forEach((_, v) => accountsTotal += v);
      for (final line in txn.lines) {
        if (line.debtId == null) continue;
        final debt = debtsById[line.debtId];
        if (debt == null) continue;
        final establishing = debt.direction == 'owe' ? 'borrow' : 'lend';
        if (line.type == establishing) {
          debtOut[line.debtId!] = (debtOut[line.debtId!] ?? 0) + line.amount;
        } else if (line.type == 'repayment') {
          debtOut[line.debtId!] = (debtOut[line.debtId!] ?? 0) - line.amount;
        }
      }
      idx++;
    }
    var payables = 0.0;
    var receivables = 0.0;
    for (final d in debts) {
      final o = debtOut[d.id] ?? 0;
      if (d.direction == 'owe') {
        payables += o;
      } else {
        receivables += o;
      }
    }
    points.add(NetWorthPoint(DateFormat('MMM').format(cursor), roundMoney(accountsTotal - payables + receivables)));
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return points;
}

// ---- financial year --------------------------------------------------------

String financialYearOf(DateTime date, int fyStartMonth) {
  final month = date.month;
  final year = date.year;
  final startYear = month >= fyStartMonth ? year : year - 1;
  if (fyStartMonth == 1) return '$startYear';
  final endShort = ((startYear + 1) % 100).toString().padLeft(2, '0');
  return '$startYear-$endShort';
}

({DateTime start, DateTime end}) financialYearRange(DateTime date, int fyStartMonth) {
  final month = date.month;
  final year = date.year;
  final startYear = month >= fyStartMonth ? year : year - 1;
  return (
    start: DateTime(startYear, fyStartMonth - 1 + 1, 1),
    end: DateTime(startYear + 1, fyStartMonth - 1 + 1, 1),
  );
}

// ---- period + trend --------------------------------------------------------

enum PeriodKind { week, month, year, fy, custom }

const periodLabels = {
  PeriodKind.week: 'This week',
  PeriodKind.month: 'This month',
  PeriodKind.year: 'This year',
  PeriodKind.fy: 'Financial year',
  PeriodKind.custom: 'Custom range',
};

({DateTime start, DateTime end}) resolvePeriod(PeriodKind kind, DateTime now, int fyStartMonth) {
  switch (kind) {
    case PeriodKind.week:
      final day = (now.weekday + 6) % 7; // Monday start
      final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: day));
      return (start: start, end: start.add(const Duration(days: 7)));
    case PeriodKind.month:
      return (start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 1));
    case PeriodKind.year:
      return (start: DateTime(now.year, 1, 1), end: DateTime(now.year + 1, 1, 1));
    case PeriodKind.fy:
      return financialYearRange(now, fyStartMonth);
    case PeriodKind.custom:
      return (start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 1));
  }
}

class TrendBucket {
  final String label;
  double income;
  double expense;
  double net;
  TrendBucket(this.label, this.income, this.expense, this.net);
}

class TrendResult {
  final List<TrendBucket> buckets;
  final double income;
  final double expense;
  final double net;
  TrendResult(this.buckets, this.income, this.expense, this.net);
}

String? _lineImpact(String type) {
  switch (type) {
    case 'income':
    case 'interest_income':
      return 'income';
    case 'expense':
    case 'interest_expense':
    case 'fee':
    case 'tax':
      return 'expense';
    default:
      return null;
  }
}

TrendResult trendSeries(List<Txn> txns, DateTime start, DateTime end) {
  final days = end.difference(start).inMilliseconds / 86400000;
  final unitDay = days <= 45;
  final buckets = <TrendBucket>[];
  final index = <String, int>{};
  String keyOf(DateTime d) => unitDay ? '${d.year}-${d.month}-${d.day}' : '${d.year}-${d.month}';
  String fmt(DateTime d) => unitDay ? '${d.day}/${d.month}' : DateFormat('MMM').format(d);

  var cursor = start;
  while (cursor.isBefore(end)) {
    index[keyOf(cursor)] = buckets.length;
    buckets.add(TrendBucket(fmt(cursor), 0, 0, 0));
    cursor = unitDay ? cursor.add(const Duration(days: 1)) : DateTime(cursor.year, cursor.month + 1, cursor.day);
  }

  var tIncome = 0.0;
  var tExpense = 0.0;
  for (final txn in txns) {
    final d = txn.date;
    if (d.isBefore(start) || !d.isBefore(end)) continue;
    final bi = index[keyOf(d)];
    if (bi == null) continue;
    for (final line in txn.lines) {
      final impact = _lineImpact(line.type);
      if (impact == 'income') {
        buckets[bi].income += line.amount;
        tIncome += line.amount;
      } else if (impact == 'expense') {
        buckets[bi].expense += line.amount;
        tExpense += line.amount;
      }
    }
  }
  for (final b in buckets) {
    b.income = roundMoney(b.income);
    b.expense = roundMoney(b.expense);
    b.net = roundMoney(b.income - b.expense);
  }
  return TrendResult(buckets, roundMoney(tIncome), roundMoney(tExpense), roundMoney(tIncome - tExpense));
}

// ---- budgets ---------------------------------------------------------------

class BudgetProgress {
  final Budget budget;
  final String categoryName;
  final double spent;
  final double limit;
  final double ratio;
  BudgetProgress(this.budget, this.categoryName, this.spent, this.limit, this.ratio);
}

List<BudgetProgress> budgetProgress(
    List<Budget> budgets, List<Txn> txns, Map<String, AppCategory> categoriesById, int fyStartMonth) {
  final now = DateTime.now();
  final monthRange = resolvePeriod(PeriodKind.month, now, fyStartMonth);
  final fyRange = financialYearRange(now, fyStartMonth);
  final out = <BudgetProgress>[];
  for (final b in budgets) {
    final range = b.period == 'yearly' ? fyRange : monthRange;
    var spent = 0.0;
    for (final t in txns) {
      if (t.date.isBefore(range.start) || !t.date.isBefore(range.end)) continue;
      for (final line in t.lines) {
        if (line.type == 'expense' && line.categoryId == b.categoryId) {
          spent += line.amount;
        }
      }
    }
    spent = roundMoney(spent);
    final ratio = b.amount > 0 ? spent / b.amount : 0.0;
    out.add(BudgetProgress(b, categoriesById[b.categoryId]?.name ?? 'AppCategory', spent, b.amount, ratio));
  }
  return out;
}

double maxOf(double a, double b) => math.max(a, b);
