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
  Membership({
    required this.id,
    required this.workspaceId,
    required this.uid,
    required this.roleId,
    this.email,
    this.displayName,
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
  final String? ifsc;
  final String? branchName;
  final String? description;
  final String? cardLast4;
  Account({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.type,
    required this.openingBalance,
    this.code,
    this.accountNumber,
    this.ifsc,
    this.branchName,
    this.description,
    this.cardLast4,
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
      ifsc: m['ifsc'],
      branchName: m['branchName'],
      description: m['description'],
      cardLast4: m['cardLast4'],
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

class Contact {
  final String id;
  final String workspaceId;
  final String name;
  final String type; // person | business
  final String? relationship; // external | family
  final String? phone;
  final String? email;
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
    this.address,
    this.notes,
    this.connectionUid,
  });
  factory Contact.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    String? firstEmail;
    final emails = m['emails'];
    if (emails is List && emails.isNotEmpty) {
      firstEmail = (emails.first as Map)['value'];
    }
    return Contact(
      id: d.id,
      workspaceId: m['workspaceId'] ?? '',
      name: m['name'] ?? '',
      type: m['type'] ?? 'person',
      relationship: m['relationship'],
      phone: m['phone'],
      email: m['email'] ?? firstEmail,
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
  });
  factory Due.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
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
  TxnLine({
    required this.lineId,
    required this.type,
    required this.amount,
    this.categoryId,
    this.debtId,
    this.toAccountId,
    this.note,
    this.external = false,
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
      lines: rawLines.map((l) => TxnLine.fromMap(Map<String, dynamic>.from(l))).toList(),
    );
  }
}
