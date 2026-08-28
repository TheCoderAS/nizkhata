// Dart ports of src/types/models.ts. Firestore doc <-> model mappers. Field
// names match the web app 1:1 so both clients read/write the same documents.

import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _ts(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

double _num(dynamic v) => (v is num) ? v.toDouble() : 0.0;

class Workspace {
  final String id;
  final String name;
  final String ownerId;
  final String baseCurrency;
  final int fyStartMonth;
  Workspace({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.baseCurrency,
    required this.fyStartMonth,
  });
  factory Workspace.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return Workspace(
      id: d.id,
      name: m['name'] ?? '',
      ownerId: m['ownerId'] ?? '',
      baseCurrency: m['baseCurrency'] ?? 'INR',
      fyStartMonth: (m['fyStartMonth'] as num?)?.toInt() ?? 4,
    );
  }
}

class Membership {
  final String id;
  final String workspaceId;
  final String uid;
  final String roleId;
  final String? email;
  final String? displayName;
  // Contact in this workspace that represents this member (auto-matched by
  // email, admin-overridable). Basis for restricted "own records only" roles.
  final String? linkedContactId;
  Membership({
    required this.id,
    required this.workspaceId,
    required this.uid,
    required this.roleId,
    this.email,
    this.displayName,
    this.linkedContactId,
  });
  factory Membership.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return Membership(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      uid: m['uid'] ?? '',
      roleId: m['roleId'] ?? '',
      email: m['email'],
      displayName: m['displayName'],
      linkedContactId: m['linkedContactId'],
    );
  }
}

class Role {
  final String id;
  final String workspaceId;
  final String name;
  final bool isSystem;
  final Map<String, bool> permissions;
  Role({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.isSystem,
    required this.permissions,
  });
  factory Role.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    final perms = <String, bool>{};
    (m['permissions'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      perms[k] = v == true;
    });
    return Role(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      name: m['name'] ?? '',
      isSystem: m['isSystem'] == true,
      permissions: perms,
    );
  }
}

class Account {
  final String id;
  final String workspaceId;
  final String name;
  final String type; // cash | bank | credit_card
  final double openingBalance;
  final String? code;
  final String? accountNumber;
  final String? cif;
  final String? ifsc;
  final String? branchName;
  final String? description;
  final String? nameOnCard;
  final String? cardLast4;
  final String? cardExpiry;
  Account({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.type,
    required this.openingBalance,
    this.code,
    this.accountNumber,
    this.cif,
    this.ifsc,
    this.branchName,
    this.description,
    this.nameOnCard,
    this.cardLast4,
    this.cardExpiry,
  });
  factory Account.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return Account(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      name: m['name'] ?? '',
      type: m['type'] ?? 'bank',
      openingBalance: _num(m['openingBalance']),
      code: m['code'],
      accountNumber: m['accountNumber'],
      cif: m['cif'],
      ifsc: m['ifsc'],
      branchName: m['branchName'],
      description: m['description'],
      nameOnCard: m['nameOnCard'],
      cardLast4: m['cardLast4'],
      cardExpiry: m['cardExpiry'],
    );
  }
}

class AppCategory {
  final String id;
  final String workspaceId;
  final String name;
  final String kind; // income | expense
  final bool isSystem;
  AppCategory({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.kind,
    required this.isSystem,
  });
  factory AppCategory.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return AppCategory(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      name: m['name'] ?? '',
      kind: m['kind'] ?? 'expense',
      isSystem: m['isSystem'] == true,
    );
  }
}

class Budget {
  final String id;
  final String workspaceId;
  final String categoryId;
  final double amount;
  final String period; // monthly | yearly
  Budget({
    required this.id,
    required this.workspaceId,
    required this.categoryId,
    required this.amount,
    required this.period,
  });
  factory Budget.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return Budget(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      categoryId: m['categoryId'] ?? '',
      amount: _num(m['amount']),
      period: m['period'] ?? 'monthly',
    );
  }
}

/// A labelled email address. A contact may have several (personal/work/etc).
/// Mirrors the web `ContactEmail` shape: `{ label, value }`.
class ContactEmail {
  final String value;
  final String label; // Personal | Work | Other
  const ContactEmail({required this.value, required this.label});

  factory ContactEmail.fromMap(Map<String, dynamic> m) => ContactEmail(
        value: (m['value'] ?? '').toString(),
        label: (m['label'] ?? 'Other').toString(),
      );

  Map<String, dynamic> toMap() => {'value': value, 'label': label};
}

class Contact {
  final String id;
  final String workspaceId;
  final String name;
  final String type; // person | business
  final String? relationship; // external | family
  final String? phone;
  final String? email; // legacy single email (derived from emails.first)
  final List<ContactEmail> emails;
  final String? address;
  final String? notes;
  final String? connectionUid;
  Contact({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.type,
    this.relationship,
    this.phone,
    this.email,
    this.emails = const [],
    this.address,
    this.notes,
    this.connectionUid,
  });
  factory Contact.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    final rawEmails = m['emails'];
    final emails = <ContactEmail>[];
    if (rawEmails is List) {
      for (final e in rawEmails) {
        if (e is Map) {
          final ce = ContactEmail.fromMap(Map<String, dynamic>.from(e));
          if (ce.value.isNotEmpty) emails.add(ce);
        }
      }
    }
    // Back-compat: fold a legacy single email into the array when present and
    // not already covered.
    final legacy = m['email'];
    if ((legacy is String) && legacy.isNotEmpty && emails.isEmpty) {
      emails.add(ContactEmail(value: legacy, label: 'Personal'));
    }
    return Contact(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      name: m['name'] ?? '',
      type: m['type'] ?? 'person',
      relationship: m['relationship'],
      phone: m['phone'],
      email: emails.isNotEmpty ? emails.first.value : (legacy is String ? legacy : null),
      emails: emails,
      address: m['address'],
      notes: m['notes'],
      connectionUid: m['connectionUid'],
    );
  }
}

class Debt {
  final String id;
  final String workspaceId;
  final String contactId;
  final String direction; // owe | owed
  final String purpose;
  final String? label;
  final String? note;
  final double principal;
  final String status; // open | settled
  // Optional simple interest (annual %, informational — never auto-posted).
  final double? interestRate;
  final DateTime? interestFrom;
  Debt({
    required this.id,
    required this.workspaceId,
    required this.contactId,
    required this.direction,
    required this.purpose,
    required this.principal,
    required this.status,
    this.label,
    this.note,
    this.interestRate,
    this.interestFrom,
  });
  factory Debt.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return Debt(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      contactId: m['contactId'] ?? '',
      direction: m['direction'] ?? 'owe',
      purpose: m['purpose'] ?? 'informal',
      principal: _num(m['principal']),
      status: m['status'] ?? 'open',
      label: m['label'],
      note: m['note'],
      interestRate: (m['interestRate'] as num?)?.toDouble(),
      interestFrom: m['interestFrom'] != null ? _ts(m['interestFrom']) : null,
    );
  }
}

class Due {
  final String id;
  final String workspaceId;
  final String direction; // payable | receivable
  final String title;
  final String? contactId;
  final String? accountId;
  final double amount;
  final DateTime dueDate;
  final String status; // open | partial | settled | cancelled
  // Transaction-shape fields so a due can be settled into a faithful
  // transaction. Optional & additive — the web app, which doesn't read them,
  // keeps working. `lines` holds full typed transaction lines (with tax info);
  // when empty, the due behaves as a legacy single-amount due.
  final String? categoryId;
  final String? note;
  final List<TxnLine> lines;
  // Recurrence: 'monthly' | 'weekly' | 'yearly'. The recurrence engine creates
  // the next instance (deterministic id) once this one settles or falls due.
  // recurrenceId groups all instances of one series (the first due's id).
  final String? recurrence;
  final String? recurrenceId;
  Due({
    required this.id,
    required this.workspaceId,
    required this.direction,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.status,
    this.contactId,
    this.accountId,
    this.categoryId,
    this.note,
    this.lines = const [],
    this.recurrence,
    this.recurrenceId,
  });
  factory Due.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    final rawLines = (m['lines'] as List?) ?? const [];
    return Due(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      direction: m['direction'] ?? 'payable',
      title: m['title'] ?? '',
      amount: _num(m['amount']),
      dueDate: _ts(m['dueDate']),
      status: m['status'] ?? 'open',
      contactId: m['contactId'],
      accountId: m['accountId'],
      categoryId: m['categoryId'],
      note: m['note'],
      recurrence: m['recurrence'],
      recurrenceId: m['recurrenceId'],
      lines: rawLines
          .whereType<Map>()
          .map((l) => TxnLine.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
    );
  }
}

class TxnLine {
  final String lineId;
  final String type;
  final double amount;
  final String? categoryId;
  final String? debtId;
  final String? toAccountId;
  final String? note;
  final bool external;
  final Map<String, dynamic>? tax; // {taxable, head, tdsAmount, taxInclusive}
  TxnLine({
    required this.lineId,
    required this.type,
    required this.amount,
    this.categoryId,
    this.debtId,
    this.toAccountId,
    this.note,
    this.external = false,
    this.tax,
  });
  factory TxnLine.fromMap(Map<String, dynamic> m) => TxnLine(
        lineId: m['lineId'] ?? '',
        type: m['type'] ?? 'expense',
        amount: _num(m['amount']),
        categoryId: m['categoryId'],
        debtId: m['debtId'],
        toAccountId: m['toAccountId'],
        note: m['note'],
        external: m['external'] == true,
        tax: m['tax'] is Map ? Map<String, dynamic>.from(m['tax']) : null,
      );
  Map<String, dynamic> toMap() => {
        'lineId': lineId,
        'type': type,
        'amount': amount,
        if (categoryId != null) 'categoryId': categoryId,
        if (debtId != null) 'debtId': debtId,
        if (toAccountId != null) 'toAccountId': toAccountId,
        if (note != null) 'note': note,
        if (external) 'external': external,
        if (tax != null) 'tax': tax,
      };
}

class Txn {
  final String id;
  final String workspaceId;
  final DateTime date;
  final String? note;
  final String accountId;
  final String? contactId;
  final double totalAmount;
  final bool hasSplit;
  final String? dueId;
  final String financialYear;
  final List<TxnLine> lines;
  // Statement-import identity (account|date|amount|ref) — lets a re-imported
  // statement recognise rows it already created, even after edits to the note.
  final String? importKey;
  // 'monthly' | 'weekly' | 'yearly': the attention strip suggests (never
  // auto-creates) the next occurrence of this transaction when it comes due.
  final String? recurrence;
  Txn({
    required this.id,
    required this.workspaceId,
    required this.date,
    required this.accountId,
    required this.totalAmount,
    required this.hasSplit,
    required this.financialYear,
    required this.lines,
    this.note,
    this.contactId,
    this.dueId,
    this.importKey,
    this.recurrence,
  });
  factory Txn.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    final rawLines = (m['lines'] as List?) ?? const [];
    return Txn(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      date: _ts(m['date']),
      note: m['note'],
      accountId: m['accountId'] ?? '',
      contactId: m['contactId'],
      totalAmount: _num(m['totalAmount']),
      hasSplit: m['hasSplit'] == true,
      dueId: m['dueId'],
      financialYear: m['financialYear'] ?? '',
      importKey: m['importKey'],
      recurrence: m['recurrence'],
      lines: rawLines.map((l) => TxnLine.fromMap(Map<String, dynamic>.from(l))).toList(),
    );
  }
}
