// Write layer — ports src/data/mutations.ts + revisions.ts. Every create/update/
// delete stamps denormalized audit Actors and appends an append-only `revisions`
// doc in the same batch, exactly like the web app, so both clients stay
// interoperable and history is consistent.

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const externalAccount = '__external__';

class Actor {
  final String uid;
  final String name;
  const Actor(this.uid, this.name);
  Map<String, dynamic> toMap() => {'uid': uid, 'name': name};

  static Actor fromUser(User? u) {
    if (u == null) return const Actor('', 'Unknown');
    final display = u.displayName?.trim() ?? '';
    final name = display.isNotEmpty
        ? display
        : (u.email != null && u.email!.isNotEmpty
            ? u.email!.toLowerCase()
            : '${u.uid.substring(0, math.min(8, u.uid.length))}…');
    return Actor(u.uid, name);
  }
}

const _ignoredRevisionFields = {
  'id',
  'workspaceId',
  'createdAt',
  'createdBy',
  'updatedAt',
  'updatedBy',
};

class Mutations {
  Mutations(this.by);
  final Actor by;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String newId(String col) => _db.collection(col).doc().id;

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

  void _appendRevision(
    WriteBatch batch, {
    required String workspaceId,
    required String entityType,
    required String entityId,
    required String action,
    Map<String, dynamic>? snapshot,
    List<String>? changedFields,
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
    if (changedFields != null && changedFields.isNotEmpty) {
      rev['changedFields'] = changedFields;
    }
    batch.set(_db.collection('revisions').doc(id), rev);
  }

  Future<String> _auditedCreate(String col, String workspaceId, Map<String, dynamic> data,
      {String? id}) async {
    final docId = id ?? newId(col);
    final clean = _strip(data);
    final batch = _db.batch();
    batch.set(_db.collection(col).doc(docId), {
      'id': docId,
      'workspaceId': workspaceId,
      ...clean,
      'createdBy': by.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _appendRevision(batch,
        workspaceId: workspaceId, entityType: col, entityId: docId, action: 'create', snapshot: clean);
    await batch.commit();
    return docId;
  }

  Future<void> _auditedUpdate(String col, String workspaceId, String id, Map<String, dynamic> data) async {
    final clean = _strip(data);
    final batch = _db.batch();
    batch.update(_db.collection(col).doc(id), {
      ...clean,
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _appendRevision(batch,
        workspaceId: workspaceId,
        entityType: col,
        entityId: id,
        action: 'update',
        snapshot: clean,
        changedFields: clean.keys.toList());
    await batch.commit();
  }

  Future<void> _auditedDelete(String col, String workspaceId, String id) async {
    final batch = _db.batch();
    batch.delete(_db.collection(col).doc(id));
    _appendRevision(batch, workspaceId: workspaceId, entityType: col, entityId: id, action: 'delete');
    await batch.commit();
  }

  // ---- contacts ----
  Future<String> createContact(String ws, Map<String, dynamic> data) => _auditedCreate('contacts', ws, data);
  Future<void> updateContact(String ws, String id, Map<String, dynamic> data) =>
      _auditedUpdate('contacts', ws, id, data);
  Future<void> deleteContact(String ws, String id) => _auditedDelete('contacts', ws, id);

  // ---- accounts ----
  Future<String> createAccount(String ws, Map<String, dynamic> data) => _auditedCreate('accounts', ws, data);
  Future<void> updateAccount(String ws, String id, Map<String, dynamic> data) =>
      _auditedUpdate('accounts', ws, id, data);
  Future<void> deleteAccount(String ws, String id) => _auditedDelete('accounts', ws, id);

  // ---- categories ----
  Future<String> createCategory(String ws, String name, String kind) =>
      _auditedCreate('categories', ws, {'name': name, 'kind': kind, 'isSystem': false});
  Future<void> updateCategory(String ws, String id, Map<String, dynamic> data) =>
      _auditedUpdate('categories', ws, id, data);
  Future<void> deleteCategory(String ws, String id) => _auditedDelete('categories', ws, id);

  // ---- budgets ----
  Future<String> createBudget(String ws, Map<String, dynamic> data) => _auditedCreate('budgets', ws, data);
  Future<void> updateBudget(String ws, String id, Map<String, dynamic> data) =>
      _auditedUpdate('budgets', ws, id, data);
  Future<void> deleteBudget(String ws, String id) => _auditedDelete('budgets', ws, id);

  // ---- dues ----
  Future<String> createDue(String ws, Map<String, dynamic> data) =>
      _auditedCreate('dues', ws, {...data, 'status': 'open'});
  Future<void> updateDue(String ws, String id, Map<String, dynamic> data) => _auditedUpdate('dues', ws, id, data);
  Future<void> deleteDue(String ws, String id) => _auditedDelete('dues', ws, id);

  // ---- debts ----
  Future<void> updateDebt(String ws, String id, Map<String, dynamic> data) =>
      _auditedUpdate('debts', ws, id, data);
  Future<void> deleteDebt(String ws, String id) => _auditedDelete('debts', ws, id);

  Map<String, dynamic> _buildTxnDoc(
    String id,
    String ws,
    Actor createdBy, {
    required DateTime date,
    String? note,
    required String accountId,
    String? contactId,
    required double totalAmount,
    String? dueId,
    required String financialYear,
    required List<Map<String, dynamic>> lines,
    Actor? updatedBy,
  }) {
    return {
      'id': id,
      'workspaceId': ws,
      'date': Timestamp.fromDate(date),
      'accountId': accountId,
      'totalAmount': totalAmount,
      'hasSplit': lines.length > 1,
      'financialYear': financialYear,
      'createdBy': createdBy.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': (updatedBy ?? createdBy).toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lines': lines.map(_strip).toList(),
      ..._strip({'note': note, 'contactId': contactId, 'dueId': dueId}),
    };
  }

  Future<String> createTransaction(
    String ws, {
    required DateTime date,
    String? note,
    required String accountId,
    String? contactId,
    required double totalAmount,
    String? dueId,
    required String financialYear,
    required List<Map<String, dynamic>> lines,
  }) async {
    final id = newId('transactions');
    final batch = _db.batch();
    batch.set(
      _db.collection('transactions').doc(id),
      _buildTxnDoc(id, ws, by,
          date: date,
          note: note,
          accountId: accountId,
          contactId: contactId,
          totalAmount: totalAmount,
          dueId: dueId,
          financialYear: financialYear,
          lines: lines),
    );
    _appendRevision(batch, workspaceId: ws, entityType: 'transactions', entityId: id, action: 'create');
    await batch.commit();
    return id;
  }

  Future<void> deleteTransaction(String ws, String id) => _auditedDelete('transactions', ws, id);

  /// Settle a due: create the txn and flip the due status in one batch.
  Future<void> settleDue(
    String ws,
    String dueId, {
    required DateTime date,
    String? note,
    required String accountId,
    String? contactId,
    required double totalAmount,
    required String financialYear,
    required List<Map<String, dynamic>> lines,
    required String newStatus,
  }) async {
    final batch = _db.batch();
    final txnId = newId('transactions');
    batch.set(
      _db.collection('transactions').doc(txnId),
      _buildTxnDoc(txnId, ws, by,
          date: date,
          note: note,
          accountId: accountId,
          contactId: contactId,
          totalAmount: totalAmount,
          dueId: dueId,
          financialYear: financialYear,
          lines: lines),
    );
    _appendRevision(batch, workspaceId: ws, entityType: 'transactions', entityId: txnId, action: 'create');
    batch.update(_db.collection('dues').doc(dueId), {
      'status': newStatus,
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _appendRevision(batch,
        workspaceId: ws, entityType: 'dues', entityId: dueId, action: 'update', changedFields: ['status']);
    await batch.commit();
  }

  /// Create a debt and, when [openingAmount] > 0, a linked opening transaction.
  Future<String> createDebtWithOpening(
    String ws,
    int fyStartMonth,
    Map<String, dynamic> debtData, {
    required double openingAmount,
    String? accountId,
    DateTime? date,
    required String Function(DateTime, int) financialYearOf,
  }) async {
    final debtId = newId('debts');
    final batch = _db.batch();
    final debtDoc = {..._strip(debtData), 'status': 'open'};
    batch.set(_db.collection('debts').doc(debtId), {
      'id': debtId,
      'workspaceId': ws,
      ...debtDoc,
      'createdBy': by.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _appendRevision(batch,
        workspaceId: ws, entityType: 'debts', entityId: debtId, action: 'create', snapshot: debtDoc);

    if (openingAmount > 0) {
      final txnId = newId('transactions');
      final external = accountId == null;
      final direction = debtData['direction'] as String;
      final lineType = direction == 'owe' ? 'borrow' : 'lend';
      final when = date ?? DateTime.now();
      final line = <String, dynamic>{
        'lineId': 'open_${when.microsecondsSinceEpoch}',
        'type': lineType,
        'amount': openingAmount,
        'debtId': debtId,
        'note': 'Opening balance',
        if (external) 'external': true,
      };
      batch.set(_db.collection('transactions').doc(txnId), {
        'id': txnId,
        'workspaceId': ws,
        'date': Timestamp.fromDate(when),
        'accountId': accountId ?? externalAccount,
        'contactId': debtData['contactId'],
        'totalAmount': external ? 0 : (direction == 'owe' ? 1 : -1) * openingAmount,
        'hasSplit': false,
        'financialYear': financialYearOf(when, fyStartMonth),
        'note': 'Opening balance',
        'createdBy': by.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedBy': by.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lines': [_strip(line)],
      });
      _appendRevision(batch, workspaceId: ws, entityType: 'transactions', entityId: txnId, action: 'create');
    }
    await batch.commit();
    return debtId;
  }
}
