// Write layer — ports src/data/mutations.ts + revisions.ts. Every create/update/
// delete stamps denormalized audit Actors and appends an append-only `revisions`
// doc in the same batch, exactly like the web app, so both clients stay
// interoperable and history is consistent.

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';

const externalAccount = '__external__';

/// Thrown by admin guardrails (last-holder, role-in-use, owner-protection).
class GuardrailException implements Exception {
  final String message;
  GuardrailException(this.message);
  @override
  String toString() => message;
}

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
    // On update an explicit null means "clear this field" — translate it to a
    // server-side delete. (Stripping nulls, as create rightly does, silently
    // kept the old value whenever a dropdown/optional field was cleared.)
    final update = <String, dynamic>{};
    data.forEach((k, v) => update[k] = v ?? FieldValue.delete());
    final batch = _db.batch();
    batch.update(_db.collection(col).doc(id), {
      ...update,
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _appendRevision(batch,
        workspaceId: workspaceId,
        entityType: col,
        entityId: id,
        action: 'update',
        snapshot: _strip(data),
        changedFields: data.keys.toList());
    await batch.commit();
  }

  Future<void> _auditedDelete(String col, String workspaceId, String id) async {
    final batch = _db.batch();
    batch.delete(_db.collection(col).doc(id));
    _appendRevision(batch, workspaceId: workspaceId, entityType: col, entityId: id, action: 'delete');
    await batch.commit();
  }

  /// Read the document's current data (for the Undo snackbar), then delete it.
  /// Returns the entity fields (audit fields stripped) or null if unreadable.
  Future<Map<String, dynamic>?> deleteWithSnapshot(String col, String ws, String id) async {
    Map<String, dynamic>? snapshot;
    try {
      final doc = await _db.collection(col).doc(id).get();
      final data = doc.data();
      if (data != null) {
        snapshot = Map<String, dynamic>.from(data)
          ..remove('createdAt')
          ..remove('createdBy')
          ..remove('updatedAt')
          ..remove('updatedBy')
          ..remove('id')
          ..remove('workspaceId');
      }
    } catch (_) {
      // Undo becomes unavailable; the delete still proceeds.
    }
    await _auditedDelete(col, ws, id);
    return snapshot;
  }

  /// Undo a delete: recreate the document under its original id with the
  /// captured fields (fresh audit stamps — the restorer owns the restore).
  Future<void> restoreEntity(String col, String ws, String id, Map<String, dynamic> data) =>
      _auditedCreate(col, ws, data, id: id);

  /// Bulk-set the category on every uncategorised income/expense line of the
  /// given transactions (used by the bulk categorisation flow). Chunked
  /// batches; lines that already have a category are left untouched.
  Future<void> bulkSetTxnCategory(String ws, List<Txn> txns, String categoryId) async {
    const chunkSize = 200;
    for (var start = 0; start < txns.length; start += chunkSize) {
      final chunk = txns.sublist(
          start, start + chunkSize > txns.length ? txns.length : start + chunkSize);
      final batch = _db.batch();
      for (final t in chunk) {
        final lines = t.lines.map((l) {
          final m = l.toMap();
          if ((l.type == 'expense' || l.type == 'income') && l.categoryId == null) {
            m['categoryId'] = categoryId;
          }
          return _strip(m);
        }).toList();
        batch.update(_db.collection('transactions').doc(t.id), {
          'lines': lines,
          'updatedBy': by.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _appendRevision(batch,
            workspaceId: ws,
            entityType: 'transactions',
            entityId: t.id,
            action: 'update',
            changedFields: ['lines']);
      }
      await batch.commit();
    }
  }

  /// Link (or clear) the contact that represents a member. Deliberately a raw
  /// single-field update: the self-service security rule only allows the
  /// `linkedContactId` key to change on one's own membership.
  Future<void> setMembershipContactLink(String membershipId, String? contactId) {
    return _db.collection('memberships').doc(membershipId).update({
      'linkedContactId': contactId ?? FieldValue.delete(),
    });
  }

  // ---- contacts ----
  Future<String> createContact(String ws, Map<String, dynamic> data) =>
      _auditedCreate('contacts', ws, _normalizeContactEmails(data));
  Future<void> updateContact(String ws, String id, Map<String, dynamic> data) =>
      _auditedUpdate('contacts', ws, id, _normalizeContactEmails(data));
  Future<void> deleteContact(String ws, String id) => _auditedDelete('contacts', ws, id);

  /// Coerce the `emails` field to the web shape — a list of `{value, label}`
  /// maps (label defaulting to "Other") with blank values dropped — and keep
  /// the legacy single `email` in sync (first address, or null when empty) so
  /// older readers stay correct.
  Map<String, dynamic> _normalizeContactEmails(Map<String, dynamic> data) {
    if (!data.containsKey('emails')) return data;
    final raw = data['emails'];
    final clean = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final value = (e['value'] ?? '').toString().trim();
          if (value.isEmpty) continue;
          final label = (e['label'] ?? '').toString().trim();
          clean.add({'value': value, 'label': label.isEmpty ? 'Other' : label});
        }
      }
    }
    final out = Map<String, dynamic>.from(data);
    out['emails'] = clean;
    out['email'] = clean.isEmpty ? null : clean.first['value'];
    return out;
  }

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
  /// [id] lets the recurrence engine use deterministic instance ids so a
  /// concurrent run on another device cannot create duplicates.
  Future<String> createDue(String ws, Map<String, dynamic> data, {String? id}) =>
      _auditedCreate('dues', ws, {...data, 'status': 'open'}, id: id);
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
    String? recurrence,
    String? notePattern,
  }) async {
    final id = newId('transactions');
    final batch = _db.batch();
    batch.set(
      _db.collection('transactions').doc(id),
      {
        ..._buildTxnDoc(id, ws, by,
            date: date,
            note: note,
            accountId: accountId,
            contactId: contactId,
            totalAmount: totalAmount,
            dueId: dueId,
            financialYear: financialYear,
            lines: lines),
        if (recurrence != null) 'recurrence': recurrence,
        if (notePattern != null) 'notePattern': notePattern,
      },
    );
    _appendRevision(batch, workspaceId: ws, entityType: 'transactions', entityId: id, action: 'create');
    await batch.commit();
    return id;
  }

  Future<void> deleteTransaction(String ws, String id) => _auditedDelete('transactions', ws, id);

  /// Bulk-create simple single-line transactions from a statement import.
  /// Committed in chunks (each txn = doc + revision = 2 writes; Firestore
  /// batches cap at 500 ops) with per-chunk progress via [onProgress].
  /// Each record: {date: DateTime, amount: signed double, note: String?,
  /// categoryId: String?, importKey: String}.
  Future<int> importTransactions(
    String ws, {
    required String accountId,
    required List<Map<String, dynamic>> records,
    required String Function(DateTime) financialYearOf,
    void Function(int done, int total)? onProgress,
  }) async {
    const chunkSize = 200;
    var written = 0;
    for (var start = 0; start < records.length; start += chunkSize) {
      final chunk = records.sublist(
          start, start + chunkSize > records.length ? records.length : start + chunkSize);
      final batch = _db.batch();
      for (final r in chunk) {
        final id = newId('transactions');
        final date = r['date'] as DateTime;
        final amount = r['amount'] as double;
        final line = <String, dynamic>{
          'lineId': '${id}_l0',
          'type': amount >= 0 ? 'income' : 'expense',
          'amount': _round2(amount.abs()),
          if (r['categoryId'] != null) 'categoryId': r['categoryId'],
        };
        batch.set(_db.collection('transactions').doc(id), {
          ..._buildTxnDoc(id, ws, by,
              date: date,
              note: r['note'] as String?,
              accountId: accountId,
              totalAmount: _round2(amount),
              financialYear: financialYearOf(date),
              lines: [line]),
          'importKey': r['importKey'],
        });
        _appendRevision(batch,
            workspaceId: ws, entityType: 'transactions', entityId: id, action: 'create');
      }
      await batch.commit();
      written += chunk.length;
      onProgress?.call(written, records.length);
    }
    return written;
  }

  /// Edit a transaction. Uses batch.update so createdBy/createdAt stay untouched
  /// (Security Rules enforce their immutability). Optional fields cleared with
  /// FieldValue.delete().
  Future<void> updateTransaction(
    String ws,
    String id, {
    required DateTime date,
    String? note,
    required String accountId,
    String? contactId,
    required double totalAmount,
    String? dueId,
    required String financialYear,
    required List<Map<String, dynamic>> lines,
    String? recurrence,
    String? notePattern,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('transactions').doc(id), {
      'date': Timestamp.fromDate(date),
      'accountId': accountId,
      'totalAmount': totalAmount,
      'hasSplit': lines.length > 1,
      'financialYear': financialYear,
      'lines': lines.map(_strip).toList(),
      'updatedBy': by.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'note': note ?? FieldValue.delete(),
      'contactId': contactId ?? FieldValue.delete(),
      'dueId': dueId ?? FieldValue.delete(),
      'recurrence': recurrence ?? FieldValue.delete(),
      'notePattern': notePattern ?? FieldValue.delete(),
    });
    _appendRevision(batch, workspaceId: ws, entityType: 'transactions', entityId: id, action: 'update');
    await batch.commit();
  }

  /// Settle a due: create the txn and flip the due status in one batch.
  /// [importKey] is stamped when the settlement came from a statement import,
  /// so re-importing the same statement flags the row as a duplicate.
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
    String? importKey,
  }) async {
    final batch = _db.batch();
    final txnId = newId('transactions');
    batch.set(
      _db.collection('transactions').doc(txnId),
      {
        ..._buildTxnDoc(txnId, ws, by,
            date: date,
            note: note,
            accountId: accountId,
            contactId: contactId,
            totalAmount: totalAmount,
            dueId: dueId,
            financialYear: financialYear,
            lines: lines),
        if (importKey != null) 'importKey': importKey,
      },
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

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// Cascade a due's descriptive fields onto the transactions settled from it
  /// (dueId link). Paid magnitude, account and date are untouched. Uses
  /// batch.update so createdBy stays immutable (Security Rules).
  ///
  /// When the due carries full [dueLines] (multi-line dues), each settlement
  /// transaction's lines are REPLACED by the due's lines scaled to that
  /// transaction's paid magnitude (so partial payments keep their proportions),
  /// and the total sign follows [dueSignedTotal]. Without lines, falls back to
  /// mirroring category / note / contact and flipping type/sign by [direction].
  Future<void> syncDueLinkedTxns(
    String ws, {
    required List<Txn> linked,
    required String direction,
    String? categoryId,
    String? note,
    String? contactId,
    List<Map<String, dynamic>>? dueLines,
    double? dueSignedTotal,
  }) async {
    if (linked.isEmpty) return;
    final hasLines = dueLines != null && dueLines.isNotEmpty && (dueSignedTotal ?? 0).abs() > 0.005;
    final newType = direction == 'payable' ? 'expense' : 'income';
    final batch = _db.batch();
    for (final t in linked) {
      List<Map<String, dynamic>> lines;
      double signed;
      if (hasLines) {
        final f = t.totalAmount.abs() / dueSignedTotal!.abs();
        var i = 0;
        lines = dueLines.map((l) {
          final m = Map<String, dynamic>.from(l);
          m['lineId'] = '${t.id}_l${i++}';
          m['amount'] = _round2(((m['amount'] as num?)?.toDouble() ?? 0) * f);
          final tax = m['tax'];
          if (tax is Map && tax['tdsAmount'] is num) {
            final t2 = Map<String, dynamic>.from(tax);
            t2['tdsAmount'] = _round2((t2['tdsAmount'] as num).toDouble() * f);
            m['tax'] = t2;
          }
          return m;
        }).toList();
        signed = _round2(dueSignedTotal.sign * t.totalAmount.abs());
      } else {
        lines = t.lines.map((l) {
          final m = l.toMap();
          if (l.type == 'income' || l.type == 'expense') m['type'] = newType;
          if (categoryId != null) {
            m['categoryId'] = categoryId;
          } else {
            m.remove('categoryId');
          }
          return m;
        }).toList();
        signed = (direction == 'payable' ? -1 : 1) * t.totalAmount.abs();
      }
      batch.update(_db.collection('transactions').doc(t.id), {
        'lines': lines.map(_strip).toList(),
        'totalAmount': signed,
        'updatedBy': by.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'note': note ?? FieldValue.delete(),
        'contactId': contactId ?? FieldValue.delete(),
      });
      _appendRevision(batch, workspaceId: ws, entityType: 'transactions', entityId: t.id, action: 'update');
    }
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

  // ---- admin: roles / members / invites / workspace ----
  // (plain writes, no revision log — mirrors src/data/adminMutations.ts)

  Future<String> createRole(String ws, String name, Map<String, bool> permissions) async {
    final id = newId('roles');
    await _db.collection('roles').doc(id).set({
      'id': id,
      'workspaceId': ws,
      'name': name,
      'isSystem': false,
      'permissions': permissions,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> updateRole(String id, {String? name, Map<String, bool>? permissions}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (permissions != null) data['permissions'] = permissions;
    await _db.collection('roles').doc(id).update(data);
  }

  Future<String> duplicateRole(String ws, Role source) =>
      createRole(ws, '${source.name} (copy)', {...source.permissions});

  Future<void> deleteRole(Role role, List<Membership> memberships) async {
    if (role.isSystem) {
      throw GuardrailException("System roles can't be deleted — duplicate to customize.");
    }
    if (memberships.any((m) => m.roleId == role.id)) {
      throw GuardrailException('This role is assigned to a member; reassign them first.');
    }
    await _db.collection('roles').doc(role.id).delete();
  }

  Future<void> changeMemberRole(Membership membership, Role newRole, String ownerId) async {
    if (membership.uid == ownerId) {
      throw GuardrailException("The workspace owner's role can't be changed.");
    }
    if (newRole.isSystem && newRole.name == 'Owner') {
      throw GuardrailException("The Owner role is reserved for the workspace owner and can't be assigned.");
    }
    await _db.collection('memberships').doc(membership.id).update({'roleId': newRole.id});
  }

  Future<void> removeMember(Membership membership, String ownerId) async {
    if (membership.uid == ownerId) {
      throw GuardrailException("The workspace owner can't be removed.");
    }
    await _db.collection('memberships').doc(membership.id).delete();
  }

  Future<void> leaveWorkspace(Membership membership, String ownerId) async {
    if (membership.uid == ownerId) {
      throw GuardrailException("The owner can't leave — transfer ownership or delete the workspace.");
    }
    await _db.collection('memberships').doc(membership.id).delete();
  }

  String inviteId(String ws, String email) => '${ws}_${email.toLowerCase()}';

  Future<String> createInvite(String ws, String email, String roleId, String invitedBy) async {
    final id = inviteId(ws, email);
    final expiresAt = Timestamp.fromDate(DateTime.now().add(const Duration(days: 14)));
    await _db.collection('invites').doc(id).set({
      'id': id,
      'workspaceId': ws,
      'email': email.toLowerCase(),
      'roleId': roleId,
      'status': 'pending',
      'invitedBy': invitedBy,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
    });
    return id;
  }

  Future<void> revokeInvite(String id) async {
    await _db.collection('invites').doc(id).update({'status': 'revoked'});
  }

  Future<void> updateWorkspace(String id, {String? name, String? baseCurrency, int? fyStartMonth}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (baseCurrency != null) data['baseCurrency'] = baseCurrency;
    if (fyStartMonth != null) data['fyStartMonth'] = fyStartMonth;
    await _db.collection('workspaces').doc(id).update(data);
  }

  Future<void> deleteWorkspace(String id, String ownerUid) async {
    final memberSnap = await _db.collection('memberships').where('workspaceId', isEqualTo: id).get();
    final others = memberSnap.docs.where((d) => d.data()['uid'] != ownerUid).toList();
    if (others.isNotEmpty) {
      final batch = _db.batch();
      for (final m in others) {
        batch.delete(m.reference);
      }
      await batch.commit();
    }
    await _db.collection('workspaces').doc(id).delete();
    await _db.collection('memberships').doc('${id}_$ownerUid').delete();
    try {
      final userRef = _db.collection('users').doc(ownerUid);
      final snap = await userRef.get();
      if (snap.data()?['lastWorkspaceId'] == id) {
        await userRef.update({'lastWorkspaceId': null});
      }
    } catch (_) {}
  }
}
