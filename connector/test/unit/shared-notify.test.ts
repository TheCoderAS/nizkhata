import { describe, expect, it } from 'vitest';

import { money, noteFor } from '../../src/jobs/shared-notify.js';

const entry = (o: Record<string, unknown> = {}) => ({
  id: 'e1', kind: 'expense', status: 'pending', creatorUid: 'asha', counterpartyUid: 'ravi', payerUid: 'asha',
  names: { asha: 'Asha', ravi: 'Ravi' }, description: 'Dinner at Bastian', amount: 1500, currency: 'INR', ...o,
});

describe('shared ledger notifications', () => {
  it('a new expense asks the other person to accept it', () => {
    expect(noteFor(entry())).toEqual({
      key: 'shared_e1_pending', to: 'ravi', route: '/shared?entry=e1',
      title: 'Asha added a shared expense', body: 'Dinner at Bastian: ₹1,500.00 for you to accept.',
    });
  });
  it('accepting and rejecting tell whoever added it', () => {
    expect(noteFor(entry({ status: 'accepted' }))).toMatchObject({ key: 'shared_e1_accepted', to: 'asha', title: 'Ravi accepted Dinner at Bastian', body: '₹1,500.00.' });
    expect(noteFor(entry({ status: 'rejected' }))).toMatchObject({ to: 'asha', title: 'Ravi rejected Dinner at Bastian', body: '₹1,500.00. Tap to sort it out.' });
  });
  it('settlements read as payments', () => {
    const s = { kind: 'settlement', creatorUid: 'ravi', counterpartyUid: 'asha', payerUid: 'ravi', description: 'Settlement', names: { ravi: 'Ravi', asha: 'Asha' } };
    expect(noteFor(entry(s))).toMatchObject({ to: 'asha', title: 'Ravi paid you back ₹1,500.00', body: 'Tap to confirm it.' });
    expect(noteFor(entry({ ...s, status: 'accepted' }))).toMatchObject({ to: 'ravi', title: 'Asha confirmed your payment', body: '₹1,500.00.' });
    expect(noteFor(entry({ ...s, status: 'rejected' }))).toMatchObject({ to: 'ravi', title: 'Asha did not confirm your payment' });
  });
  it('the amount stays in the entry\'s own currency, old entries are rupees', () => {
    expect(noteFor(entry({ amount: 40, currency: 'USD' }))!.body).toBe('Dinner at Bastian: $40.00 for you to accept.');
    expect(noteFor(entry({ currency: undefined }))!.body).toContain('₹1,500.00');
    expect(money(1500, 'JPY', 'en_US')).toBe('¥1,500');
  });
  it('nothing for an entry without both people', () => {
    expect(noteFor(entry({ counterpartyUid: '' }))).toBeNull();
    expect(noteFor(entry({ status: 'weird' }))).toBeNull();
  });
});
