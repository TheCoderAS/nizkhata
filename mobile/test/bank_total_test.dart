// The dashboard's headline "In bank accounts" figure.
//
// It answers "how much have I got in the bank", so cash in hand is out (it is
// not in an account) and a credit card is out (it is a liability, and its
// negative balance would subtract from a figure about what you hold).
// Net worth is where everything nets off; this is not that.

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/derive.dart';
import 'package:nizkhata/data/models.dart';

Account _acct(String id, String type) =>
    Account(id: id, workspaceId: 'ws', name: id, type: type, openingBalance: 0);

void main() {
  final accounts = [
    _acct('hdfc', 'bank'),
    _acct('sbi', 'bank'),
    _acct('wallet', 'cash'),
    _acct('icici_card', 'credit_card'),
  ];
  final balances = {
    'hdfc': 82000.0,
    'sbi': 18000.0,
    'wallet': 3500.0,
    'icici_card': -32304.03,
  };
  double balanceOf(String id) => balances[id] ?? 0;

  test('adds up the bank accounts and nothing else', () {
    expect(bankBalanceTotal(accounts, balanceOf), 100000);
  });

  test('a drawn credit card does not drag it down', () {
    // The whole point: the card owes ₹32,304.03, and this figure is unmoved.
    expect(bankBalanceTotal([_acct('icici_card', 'credit_card')], balanceOf), 0);
  });

  test('cash in hand is not in an account', () {
    expect(bankBalanceTotal([_acct('wallet', 'cash')], balanceOf), 0);
  });

  test('an overdrawn bank account does count against it', () {
    // Being in the red at the bank is genuinely less money in the bank.
    expect(
      bankBalanceTotal(
          [_acct('hdfc', 'bank'), _acct('od', 'bank')], (id) => id == 'od' ? -12000 : balanceOf(id)),
      70000,
    );
  });

  test('no accounts at all is zero, not a crash', () {
    expect(bankBalanceTotal(const [], balanceOf), 0);
  });
}
