// Cross-user shared ledger (Splitwise-style) — Dart port of
// src/data/sharedMutations.ts (+ the SharedConnection/ShareInvite/SharedEntry
// models from models.ts and the sharedBalances derivation from derive.ts).
//
// Unlike `mutations.dart`, these touch collections keyed by user uid rather than
// workspaceId: `shareInvites`, `sharedConnections`, `sharedEntries`. The model
// (agreed with the spec owner):
//
//   - A shared item is strictly BILATERAL (creator <-> one counterparty). A
//     multi-person split is several bilateral entries created together, so each
//     counterparty consents to their own claim independently.
//   - The creator already paid, so their side records the money movement
//     IMMEDIATELY (a real account-linked transaction). A rejection by the
//     counterparty becomes a conflict the creator resolves (absorb / remove).
//   - The counterparty is BALANCE-ONLY: accepting records an account-less
//     (external) debt that tracks "I owe you" without touching their accounts
//     until an actual settlement moves money.
//   - Each side reflects into ITS OWN workspace only (never the other's), so
//     Security Rules are never crossed. The cross-user `sharedEntries` doc is
//     the consent layer; the local `debts`/`transactions` are each book's
//     private handle, linked back by `sharedEntryId`.
//
// No revision log is written for the cross-user docs themselves (they are not
// workspace entities); the workspace-local reflections are fully audited (they
// reuse the same audit + revision shapes as mutations.dart, duplicated here).
//
// Currency. Each workspace keeps its books in one currency, and the two parties
// may keep theirs in different ones. So every entry carries the currency of the
// books it was created from, and is always shown in that currency. Nothing is
// ever converted: an entry is only written into books kept in its own currency
// (see [SharedCurrencyMismatch]). Entries from before the field existed were
// all created from INR books, which is how a missing field is read.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/currency.dart';
import 'derive.dart';
import 'models.dart';
import 'mutations.dart' show Actor, externalAccount;

// ---- ids -------------------------------------------------------------------

/// Sorted-pair connection id, stable regardless of who initiates.
String connectionIdFor(String a, String b) {
  final pair = [a, b]..sort();
  return '${pair[0]}_${pair[1]}';
}

/// Deterministic share-invite id (mirrors workspace invites).
String shareInviteId(String fromUid, String email) => '${fromUid}_${email.toLowerCase()}';

// ---- models (ports of the shared docs in models.ts) ------------------------

Map<String, String> _strMap(dynamic v) {
  final out = <String, String>{};
  if (v is Map) {
    v.forEach((k, val) => out['$k'] = '$val');
  }
  return out;
}

List<String> _strList(dynamic v) {
  if (v is List) return v.map((e) => '$e').toList();
  return const [];
}

DateTime _toDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

class SharedConnection {
  final String id;
  final List<String> uids;
  final Map<String, String> names;
  final Map<String, String> emails;
  final String status;
  SharedConnection({
    required this.id,
    required this.uids,
    required this.names,
    required this.emails,
    required this.status,
  });
  factory SharedConnection.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return SharedConnection(
      id: d.id,
      uids: _strList(m['uids']),
      names: _strMap(m['names']),
      emails: _strMap(m['emails']),
      status: m['status'] ?? 'active',
    );
  }
}

class ShareInvite {
  final String id;
  final String fromUid;
  final String fromName;
  final String fromEmail;
  final String toEmail;
  final String status; // pending | accepted | revoked
  ShareInvite({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromEmail,
    required this.toEmail,
    required this.status,
  });
  factory ShareInvite.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return ShareInvite(
      id: d.id,
      fromUid: m['fromUid'] ?? '',
      fromName: m['fromName'] ?? '',
      fromEmail: m['fromEmail'] ?? '',
      toEmail: m['toEmail'] ?? '',
      status: m['status'] ?? 'pending',
    );
  }
}

class SharedEntry {
  final String id;
  final String connectionId;
  final String kind; // expense | settlement
  final List<String> uids;
  final String creatorUid;
  final String counterpartyUid;
  final Map<String, String> names;
  final String payerUid;
  final String description;
  final double amount;
  final DateTime date;
  final String status; // pending | accepted | rejected
  final List<String> pendingForUids;
  final bool resolved;

  /// ISO code of the books the creator recorded this from. [amount] is a
  /// figure in this currency, whatever the reader's own books are kept in.
  final String currency;
  SharedEntry({
    required this.id,
    required this.connectionId,
    required this.kind,
    required this.uids,
    required this.creatorUid,
    required this.counterpartyUid,
    required this.names,
    required this.payerUid,
    required this.description,
    required this.amount,
    required this.date,
    required this.status,
    required this.pendingForUids,
    required this.resolved,
    this.currency = 'INR',
  });
  factory SharedEntry.fromDoc(DocumentSnapshot d) =>
      SharedEntry.fromMap(d.id, d.data() as Map<String, dynamic>);

  factory SharedEntry.fromMap(String id, Map<String, dynamic> m) {
    return SharedEntry(
      id: id,
      connectionId: m['connectionId'] ?? '',
      kind: m['kind'] ?? 'expense',
      uids: _strList(m['uids']),
      creatorUid: m['creatorUid'] ?? '',
      counterpartyUid: m['counterpartyUid'] ?? '',
      names: _strMap(m['names']),
      payerUid: m['payerUid'] ?? '',
      description: m['description'] ?? '',
      amount: (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0.0,
      date: _toDate(m['date']),
      status: m['status'] ?? 'pending',
      pendingForUids: _strList(m['pendingForUids']),
      resolved: m['resolved'] == true,
      currency: sharedEntryCurrency(m['currency']),
    );
  }
}

/// The currency a stored entry is in. Entries written before the field existed
/// came from INR books, the only kind there were, so a missing (or unreadable)
/// value is INR rather than the reader's own currency.
String sharedEntryCurrency(dynamic stored) {
  if (stored is String && RegExp(r'^[A-Za-z]{3}$').hasMatch(stored)) return stored.toUpperCase();
  return 'INR';
}

/// Raised instead of writing a shared item into books kept in another currency.
///
/// The two figures are in different units, so there is no honest way to record
/// one in the other's books without an exchange rate, and the app keeps none.
/// Posting the bare number would turn \$50 into ₹50. The person can still see
/// and reject the item from anywhere; recording it takes a workspace kept in
/// the item's own currency.
class SharedCurrencyMismatch implements Exception {
  final String entryCurrency;
  final String bookCurrency;
  SharedCurrencyMismatch(this.entryCurrency, this.bookCurrency);

  String get message => sharedCurrencyNote(entryCurrency, bookCurrency)!;

  @override
  String toString() => message;
}

/// Why an item in [entryCurrency] cannot be recorded in books kept in
/// [bookCurrency], in words for the screen; null when it can.
String? sharedCurrencyNote(String entryCurrency, String bookCurrency) {
  if (entryCurrency == bookCurrency) return null;
  final spec = currencySpec(entryCurrency);
  return 'This is in ${spec.code} (${spec.name}), and this workspace keeps its books in '
      '$bookCurrency. Amounts are never converted, so to record it, open a workspace kept in '
      '${spec.code}.';
}

void _ensureSameCurrency(String entryCurrency, String bookCurrency) {
  if (entryCurrency != bookCurrency) throw SharedCurrencyMismatch(entryCurrency, bookCurrency);
}

/// [roundMoney] rounds to the ACTIVE workspace's currency, but a shared
/// balance is in its entries' currency, which may be another one (whole yen
/// against two-decimal rupees).
double _roundIn(num n, String currency) {
  final f = _pow10(currencySpec(currency).decimals);
  return ((n + 1e-9) * f).round() / f;
}

// ---- shared balances (port of derive.ts sharedBalances) --------------------
// Balances are derived from AGREED shared entries (status "accepted"), plus the
// creator's side of still-pending EXPENSES/SETTLEMENTS (they already moved the
// money, so the claim stands until rejected). A rejected entry contributes 0.

class SharedBalance {
  final String uid; // the counterparty (from my perspective)
  final String name;
  final double net; // > 0 they owe me; < 0 I owe them
  final String currency; // what [net] is counted in
  SharedBalance(this.uid, this.name, this.net, [this.currency = 'INR']);
}

/// Net shared balance per counterparty AND currency, from `myUid`'s
/// perspective. The same two people can share from books in different
/// currencies (one of them keeps a rupee workspace and a dollar one), and a
/// rupee and a dollar do not net against each other, so each currency is its
/// own balance.
List<SharedBalance> sharedBalances(String myUid, List<SharedEntry> entries) {
  final net = <(String, String), double>{};
  final name = <String, String>{};

  for (final e in entries) {
    if (e.status == 'rejected') continue;
    // Pending entries only count on the side that already moved money: the
    // creator of an expense, or the payer of a settlement (also the creator).
    if (e.status == 'pending' && e.creatorUid != myUid) continue;

    final other = e.creatorUid == myUid ? e.counterpartyUid : e.creatorUid;
    name[other] = e.names[other] ?? other;

    // + if I paid, - if I received: the payer always moves the balance in
    // their own favour, for both expenses and settlements.
    final delta = e.payerUid == myUid ? e.amount : -e.amount;
    final key = (other, e.currency);
    net[key] = (net[key] ?? 0) + delta;
  }

  final out = <SharedBalance>[];
  net.forEach((key, n) {
    final (uid, currency) = key;
    final rounded = _roundIn(n, currency);
    // Below half a minor unit a balance is nothing (half a yen, not 0.005).
    if (rounded.abs() < 0.5 / _pow10(currencySpec(currency).decimals)) return;
    out.add(SharedBalance(uid, name[uid] ?? uid, rounded, currency));
  });
  out.sort((a, b) => b.net.compareTo(a.net));
  return out;
}

double _pow10(int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

// ---- inputs ----------------------------------------------------------------

class SharedExpenseParticipant {
  final String counterpartyUid;
  final String counterpartyName;
  final String connectionId;
  final double share; // their portion (> 0)
  SharedExpenseParticipant({
    required this.counterpartyUid,
    required this.counterpartyName,
    required this.connectionId,
    required this.share,
  });
}

// ---- reflection context ----------------------------------------------------
// Each side mirrors an agreed shared item into its own workspace using the
// normal debt/transaction engine. These find-or-create the local handle (a
// hidden contact tagged with the counterparty's uid) and an aggregate "shared"
// debt per direction, accumulating new docs so repeated calls dedupe too.

class _ReflectionCtx {
  final String workspaceId;
  final int fyStartMonth;
  final List<Contact> contacts; // existing local contacts (for dedupe)
  final List<Debt> debts; // existing local debts (for dedupe)
  final List<Contact> newContacts = []; // docs created earlier in THIS batch
  final List<Debt> newDebts = [];
  _ReflectionCtx({
    required this.workspaceId,
    required this.fyStartMonth,
    required this.contacts,
    required this.debts,
  });
}

const _ignoredRevisionFields = {
  'id',
  'workspaceId',
  'createdAt',
  'createdBy',
  'updatedAt',
  'updatedBy',
};

/// Faithful port of the exported functions in sharedMutations.ts. Constructed
/// with the current user's identity so it can stamp both the cross-user docs
/// (denormalized names) and the workspace-local reflections (audit Actors).
class SharedMutations {
  SharedMutations({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.by,
  });

  final String uid;
  final String? displayName;
  final String email; // the current user's email
  final Actor by; // Actor.fromUser(user); by.name == actorName(me)

  // Late, so the currency guards below run (and can be tested) before anything
  // reaches for Firestore.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  String newId(String col) => _db.collection(col).doc().id;

  String get _actorName => by.name;
  String get _myEmail => email.toLowerCase();

  Map<String, dynamic> _strip(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (v != null) out[k] = v;
    });
    return out;
  }

  Map<String, dynamic> _sanitize(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (v == null || _ignoredRevisionFields.contains(k)) return;
      out[k] = v;
    });
    return out;
  }

  // Local reflections are fully audited — same shapes as mutations.dart.
  void _appendRevision(
    WriteBatch batch, {
    required String workspaceId,
    required String entityType,
    required String entityId,
    required String action,
    Map<String, dynamic>? snapshot,
  }) {
    final id = newId('revisions');
    final rev = <String, dynamic>{
      'id': id,
      'workspaceId': workspaceId,
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'by': by.toMap(),
      'at': FieldValue.serverTimestamp(),
    };
    if (snapshot != null) rev['snapshot'] = _sanitize(snapshot);
    batch.set(_db.collection('revisions').doc(id), rev);
  }

  // ---- reflection helpers --------------------------------------------------

  Contact? _matchContact(_ReflectionCtx ctx, String connectionUid) {
    for (final c in ctx.contacts) {
      if (c.connectionUid == connectionUid) return c;
    }
    for (final c in ctx.newContacts) {
      if (c.connectionUid == connectionUid) return c;
    }
    return null;
  }

  String _findOrCreateSharedContact(
    WriteBatch batch,
    _ReflectionCtx ctx,
    String connectionUid,
    String name,
  ) {
    final hit = _matchContact(ctx, connectionUid);
    if (hit != null) return hit.id;

    final id = newId('contacts');
    final snapshot = <String, dynamic>{'name': name, 'type': 'person', 'connectionUid': connectionUid};
    batch.set(_db.collection('contacts').doc(id), {
      'id': id,
      'workspaceId': ctx.workspaceId,
      ...snapshot,
      'createdBy': by.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _appendRevision(batch,
        workspaceId: ctx.workspaceId,
        entityType: 'contacts',
        entityId: id,
        action: 'create',
        snapshot: snapshot);
    ctx.newContacts.add(Contact(
      id: id,
      workspaceId: ctx.workspaceId,
      name: name,
      type: 'person',
      connectionUid: connectionUid,
    ));
    return id;
  }

  Debt? _matchDebt(_ReflectionCtx ctx, String contactId, String direction) {
    bool m(Debt d) => d.purpose == 'shared' && d.contactId == contactId && d.direction == direction;
    for (final d in ctx.debts) {
      if (m(d)) return d;
    }
    for (final d in ctx.newDebts) {
      if (m(d)) return d;
    }
    return null;
  }

  String _findOrCreateSharedDebt(
    WriteBatch batch,
    _ReflectionCtx ctx,
    String contactId,
    String direction,
  ) {
    final hit = _matchDebt(ctx, contactId, direction);
    if (hit != null) return hit.id;

    final id = newId('debts');
    final snapshot = <String, dynamic>{
      'contactId': contactId,
      'direction': direction,
      'purpose': 'shared',
      'principal': 0,
      'status': 'open',
    };
    batch.set(_db.collection('debts').doc(id), {
      'id': id,
      'workspaceId': ctx.workspaceId,
      ...snapshot,
      'createdBy': by.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _appendRevision(batch,
        workspaceId: ctx.workspaceId,
        entityType: 'debts',
        entityId: id,
        action: 'create',
        snapshot: snapshot);
    ctx.newDebts.add(Debt(
      id: id,
      workspaceId: ctx.workspaceId,
      contactId: contactId,
      direction: direction,
      purpose: 'shared',
      principal: 0,
      status: 'open',
    ));
    return id;
  }

  /// Append a reflection transaction (single line) to the batch.
  void _addReflectionTxn(
    WriteBatch batch,
    _ReflectionCtx ctx, {
    required String sharedEntryId,
    required String contactId,
    required String accountId, // externalAccount for balance-only
    required Map<String, dynamic> line,
    required double totalAmount,
    required DateTime date,
    required String note,
  }) {
    final id = newId('transactions');
    batch.set(_db.collection('transactions').doc(id), {
      'id': id,
      'workspaceId': ctx.workspaceId,
      'date': Timestamp.fromDate(date),
      'accountId': accountId,
      'contactId': contactId,
      'sharedEntryId': sharedEntryId,
      'totalAmount': totalAmount,
      'hasSplit': false,
      'financialYear': financialYearOf(date, ctx.fyStartMonth),
      'note': note,
      'createdBy': by.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lines': [_strip(line)],
    });
    _appendRevision(batch,
        workspaceId: ctx.workspaceId, entityType: 'transactions', entityId: id, action: 'create');
  }

  // ---- invites & connections ----------------------------------------------

  /// Invite another user (by email) to share. Idempotent on (me, email).
  Future<String> inviteSharedPartner(String toEmail) async {
    final email = toEmail.trim().toLowerCase();
    final id = shareInviteId(uid, email);
    final expiresAt = Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)));
    await _db.collection('shareInvites').doc(id).set({
      'id': id,
      'fromUid': uid,
      'fromName': _actorName,
      'fromEmail': _myEmail,
      'toEmail': email,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
    });
    return id;
  }

  Future<void> revokeShareInvite(String id) async {
    await _db.collection('shareInvites').doc(id).update({'status': 'revoked'});
  }

  /// Establish (or refresh) the connection between two users and mark the
  /// originating invite accepted. Called at onboarding when the invitee signs in.
  Future<String> acceptShareInvite({
    required String inviteId,
    required String fromUid,
    required String fromName,
    required String fromEmail,
  }) async {
    final connId = connectionIdFor(fromUid, uid);
    final batch = _db.batch();
    final sortedUids = [fromUid, uid]..sort();
    batch.set(_db.collection('sharedConnections').doc(connId), {
      'id': connId,
      'uids': sortedUids,
      'names': {fromUid: fromName, uid: _actorName},
      'emails': {fromUid: fromEmail, uid: _myEmail},
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('shareInvites').doc(inviteId), {'status': 'accepted'},
        SetOptions(merge: true));
    await batch.commit();
    return connId;
  }

  // ---- create a shared expense (creator side) -----------------------------

  /// Record an expense the creator paid and split with one or more counterparties.
  /// In a single batch: one bilateral `sharedEntry` per counterparty (pending),
  /// the creator's own-share expense (if myShare > 0), and a `lend` reflection
  /// transaction per counterparty (real account; they owe the creator).
  ///
  /// [currency] is the workspace's own: the amounts were entered in it and the
  /// creator's side is recorded in it, so each entry carries it for the
  /// counterparty to read.
  Future<void> createSharedExpense({
    required String workspaceId,
    required String currency,
    required int fyStartMonth,
    required String accountId,
    required String description,
    required DateTime date,
    required double myShare,
    String? myCategoryId,
    required List<SharedExpenseParticipant> participants,
    required List<Contact> contacts,
    required List<Debt> debts,
  }) async {
    final batch = _db.batch();
    final ctx = _ReflectionCtx(
        workspaceId: workspaceId, fyStartMonth: fyStartMonth, contacts: contacts, debts: debts);

    // Creator's own share is a plain expense (no shared entry, no contact).
    if (myShare > 0) {
      final id = newId('transactions');
      batch.set(_db.collection('transactions').doc(id), {
        'id': id,
        'workspaceId': workspaceId,
        'date': Timestamp.fromDate(date),
        'accountId': accountId,
        'totalAmount': -myShare,
        'hasSplit': false,
        'financialYear': financialYearOf(date, fyStartMonth),
        'note': '$description (my share)',
        'createdBy': by.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedBy': by.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lines': [
          _strip({
            'lineId': 'share_${DateTime.now().millisecondsSinceEpoch}',
            'type': 'expense',
            'amount': myShare,
            'categoryId': myCategoryId,
            'note': 'My share',
          }),
        ],
      });
      _appendRevision(batch,
          workspaceId: workspaceId, entityType: 'transactions', entityId: id, action: 'create');
    }

    for (final p in participants) {
      final entryId = newId('sharedEntries');
      final uids = [uid, p.counterpartyUid];
      batch.set(_db.collection('sharedEntries').doc(entryId), {
        'id': entryId,
        'connectionId': p.connectionId,
        'kind': 'expense',
        'uids': uids,
        'creatorUid': uid,
        'counterpartyUid': p.counterpartyUid,
        'names': {uid: _actorName, p.counterpartyUid: p.counterpartyName},
        'payerUid': uid,
        'description': description,
        'amount': p.share,
        'currency': currency,
        'date': Timestamp.fromDate(date),
        'status': 'pending',
        'pendingForUids': [p.counterpartyUid],
        'createdBy': by.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedBy': by.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Reflect: they owe me (an "owed" shared debt); money left my account.
      final contactId = _findOrCreateSharedContact(batch, ctx, p.counterpartyUid, p.counterpartyName);
      final debtId = _findOrCreateSharedDebt(batch, ctx, contactId, 'owed');
      _addReflectionTxn(batch, ctx,
          sharedEntryId: entryId,
          contactId: contactId,
          accountId: accountId,
          line: {
            'lineId': 'lend_$entryId',
            'type': 'lend',
            'amount': p.share,
            'debtId': debtId,
            'note': description,
          },
          totalAmount: -p.share,
          date: date,
          note: description);
    }

    await batch.commit();
  }

  // ---- respond to a shared expense (counterparty side) --------------------

  /// Accept a shared expense: flip my consent and record a BALANCE-ONLY debt
  /// (external borrow — I owe the creator) that doesn't touch my accounts.
  ///
  /// [bookCurrency] is the currency of the workspace it would be recorded in;
  /// an entry in any other currency is refused, not recorded as a bare number.
  Future<void> acceptSharedExpense({
    required SharedEntry entry,
    required String workspaceId,
    required String bookCurrency,
    required int fyStartMonth,
    required List<Contact> contacts,
    required List<Debt> debts,
  }) async {
    _ensureSameCurrency(entry.currency, bookCurrency);
    final batch = _db.batch();
    batch.update(_db.collection('sharedEntries').doc(entry.id), {
      'status': 'accepted',
      'pendingForUids': <String>[],
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final ctx = _ReflectionCtx(
        workspaceId: workspaceId, fyStartMonth: fyStartMonth, contacts: contacts, debts: debts);
    final creatorName = entry.names[entry.creatorUid] ?? 'Partner';
    final contactId = _findOrCreateSharedContact(batch, ctx, entry.creatorUid, creatorName);
    final debtId = _findOrCreateSharedDebt(batch, ctx, contactId, 'owe');
    _addReflectionTxn(batch, ctx,
        sharedEntryId: entry.id,
        contactId: contactId,
        accountId: externalAccount, // balance-only until I actually settle
        line: {
          'lineId': 'borrow_${entry.id}',
          'type': 'borrow',
          'amount': entry.amount,
          'debtId': debtId,
          'note': entry.description,
          'external': true,
        },
        totalAmount: 0,
        date: entry.date,
        note: entry.description);

    await batch.commit();
  }

  /// Reject a shared expense: flip only my consent (no local reflection).
  Future<void> rejectSharedEntry(SharedEntry entry) async {
    await _db.collection('sharedEntries').doc(entry.id).update({
      'status': 'rejected',
      'pendingForUids': <String>[],
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- settlement ----------------------------------------------------------

  /// Propose a settlement: I (the payer) assert I paid the counterparty `amount`.
  /// Records my real outflow now (a `repayment` reducing my "owe" shared debt)
  /// and creates a pending settlement entry the counterparty must accept.
  /// [currency] is the workspace's own, as for [createSharedExpense].
  Future<void> proposeSettlement({
    required String counterpartyUid,
    required String counterpartyName,
    required String connectionId,
    required double amount,
    required String description,
    required DateTime date,
    required String workspaceId,
    required String currency,
    required int fyStartMonth,
    required String accountId,
    required List<Contact> contacts,
    required List<Debt> debts,
  }) async {
    final batch = _db.batch();
    final entryId = newId('sharedEntries');
    final uids = [uid, counterpartyUid];

    batch.set(_db.collection('sharedEntries').doc(entryId), {
      'id': entryId,
      'connectionId': connectionId,
      'kind': 'settlement',
      'uids': uids,
      'creatorUid': uid,
      'counterpartyUid': counterpartyUid,
      'names': {uid: _actorName, counterpartyUid: counterpartyName},
      'payerUid': uid,
      'description': description,
      'amount': amount,
      'currency': currency,
      'date': Timestamp.fromDate(date),
      'status': 'pending',
      'pendingForUids': [counterpartyUid],
      'createdBy': by.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final ctx = _ReflectionCtx(
        workspaceId: workspaceId, fyStartMonth: fyStartMonth, contacts: contacts, debts: debts);
    // I pay down what I owe them: a repayment against my "owe" shared debt.
    final contactId = _findOrCreateSharedContact(batch, ctx, counterpartyUid, counterpartyName);
    final debtId = _findOrCreateSharedDebt(batch, ctx, contactId, 'owe');
    _addReflectionTxn(batch, ctx,
        sharedEntryId: entryId,
        contactId: contactId,
        accountId: accountId,
        line: {
          'lineId': 'settle_$entryId',
          'type': 'repayment',
          'amount': amount,
          'debtId': debtId,
          'note': description,
        },
        totalAmount: -amount, // repayment of an "owe" debt: money out
        date: date,
        note: description);

    await batch.commit();
  }

  /// Accept a settlement the counterparty proposed: flip my consent and record
  /// the matching inflow (a `repayment` of my "owed" shared debt).
  ///
  /// Refused, like [acceptSharedExpense], when the settlement is in another
  /// currency than [bookCurrency]: the inflow would land in a real account.
  Future<void> acceptSettlement({
    required SharedEntry entry,
    required String workspaceId,
    required String bookCurrency,
    required int fyStartMonth,
    required List<Contact> contacts,
    required List<Debt> debts,
    String? accountId,
  }) async {
    _ensureSameCurrency(entry.currency, bookCurrency);
    final batch = _db.batch();
    batch.update(_db.collection('sharedEntries').doc(entry.id), {
      'status': 'accepted',
      'pendingForUids': <String>[],
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final ctx = _ReflectionCtx(
        workspaceId: workspaceId, fyStartMonth: fyStartMonth, contacts: contacts, debts: debts);
    final payerName = entry.names[entry.payerUid] ?? 'Partner';
    final contactId = _findOrCreateSharedContact(batch, ctx, entry.payerUid, payerName);
    final debtId = _findOrCreateSharedDebt(batch, ctx, contactId, 'owed');
    // The receiver records the inflow against a real account chosen in the UI;
    // if none is given the inflow is balance-only (external).
    final real = accountId != null;
    _addReflectionTxn(batch, ctx,
        sharedEntryId: entry.id,
        contactId: contactId,
        accountId: accountId ?? externalAccount,
        line: {
          'lineId': 'settle_${entry.id}',
          'type': 'repayment',
          'amount': entry.amount,
          'debtId': debtId,
          'note': entry.description,
          if (!real) 'external': true,
        },
        totalAmount: real ? entry.amount : 0,
        date: entry.date,
        note: entry.description);

    await batch.commit();
  }

  // ---- conflict resolution (creator side) ---------------------------------

  /// Resolve a rejected shared expense on the creator's side.
  ///   - "absorb": rewrite the reflection so the amount becomes the creator's
  ///     own expense instead of a receivable, and clear the conflict.
  ///   - "remove": delete the reflection transaction, and clear the conflict.
  /// The shared entry is marked resolved either way so the banner clears.
  ///
  /// Both modes rewrite the books the expense was recorded in, so both are
  /// refused from a workspace kept in another currency than the entry's: the
  /// reflection is not in those books, and an absorbed expense would be.
  Future<void> resolveConflict({
    required SharedEntry entry,
    required String mode, // absorb | remove
    required String reflectionTxnId,
    String? myCategoryId,
    required int fyStartMonth,
    required DateTime date,
    required String accountId,
    required String workspaceId,
    required String bookCurrency,
  }) async {
    _ensureSameCurrency(entry.currency, bookCurrency);
    final batch = _db.batch();

    if (mode == 'absorb') {
      // Rewrite the reflection transaction: lend -> expense (my own cost).
      batch.set(_db.collection('transactions').doc(reflectionTxnId), {
        'id': reflectionTxnId,
        'workspaceId': workspaceId,
        'date': Timestamp.fromDate(date),
        'accountId': accountId,
        'sharedEntryId': entry.id,
        'totalAmount': -entry.amount,
        'hasSplit': false,
        'financialYear': financialYearOf(date, fyStartMonth),
        'note': '${entry.description} (absorbed)',
        'createdBy': by.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedBy': by.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lines': [
          _strip({
            'lineId': 'absorb_${entry.id}',
            'type': 'expense',
            'amount': entry.amount,
            'categoryId': myCategoryId,
            'note': 'Absorbed shared share',
          }),
        ],
      });
      _appendRevision(batch,
          workspaceId: workspaceId,
          entityType: 'transactions',
          entityId: reflectionTxnId,
          action: 'update');
    } else {
      batch.delete(_db.collection('transactions').doc(reflectionTxnId));
      _appendRevision(batch,
          workspaceId: workspaceId,
          entityType: 'transactions',
          entityId: reflectionTxnId,
          action: 'delete');
    }

    batch.update(_db.collection('sharedEntries').doc(entry.id), {
      'resolved': true,
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Re-bill a rejected expense: ask the counterparty again. The old (rejected)
  /// entry is marked resolved and a fresh pending entry is created for the same
  /// claim; the creator's existing reflection transaction is re-pointed at the
  /// new entry so the money already spent stays linked to the live claim.
  Future<String> rebillSharedEntry({
    required SharedEntry entry,
    String? reflectionTxnId,
  }) async {
    final batch = _db.batch();
    final newEntryId = newId('sharedEntries');

    batch.set(_db.collection('sharedEntries').doc(newEntryId), {
      'id': newEntryId,
      'connectionId': entry.connectionId,
      'kind': entry.kind,
      'uids': entry.uids,
      'creatorUid': entry.creatorUid,
      'counterpartyUid': entry.counterpartyUid,
      'names': entry.names,
      'payerUid': entry.payerUid,
      'description': entry.description,
      'amount': entry.amount,
      // The same claim, so the same currency. Written out even for an old
      // entry that had none, where it was INR all along.
      'currency': entry.currency,
      'date': Timestamp.fromDate(entry.date),
      'status': 'pending',
      'pendingForUids': [entry.counterpartyUid],
      'createdBy': by.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Clear the old conflict.
    batch.update(_db.collection('sharedEntries').doc(entry.id), {
      'resolved': true,
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Re-point the existing reflection transaction at the new entry, if present.
    if (reflectionTxnId != null) {
      batch.update(_db.collection('transactions').doc(reflectionTxnId), {
        'sharedEntryId': newEntryId,
        'updatedBy': by.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return newEntryId;
  }

  /// Withdraw a shared entry the creator authored (also drops the reflection).
  Future<void> withdrawSharedEntry(SharedEntry entry, String? reflectionTxnId) async {
    final batch = _db.batch();
    batch.delete(_db.collection('sharedEntries').doc(entry.id));
    if (reflectionTxnId != null) {
      batch.delete(_db.collection('transactions').doc(reflectionTxnId));
      _appendRevision(batch,
          workspaceId: entry.uids.isNotEmpty ? entry.uids[0] : '', // best-effort
          entityType: 'transactions',
          entityId: reflectionTxnId,
          action: 'delete');
    }
    await batch.commit();
  }
}
