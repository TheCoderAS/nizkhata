// The shareable khata: a branded per-contact ledger PDF generated entirely
// on-device with Syncfusion (the same library that parses statement PDFs) and
// handed to the share sheet. This is the artifact people forward on WhatsApp:
// "here's our history, this is where we stand."

import 'dart:typed_data';
import 'dart:ui' show Color, Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'pdf_brand.dart';

class KhataDueLine {
  final String title;
  final DateTime dueDate;
  final double remaining;
  final String direction; // payable | receivable
  KhataDueLine(this.title, this.dueDate, this.remaining, this.direction);
}

class KhataEntry {
  final DateTime date;
  final String description;
  final double amount; // signed account effect: + money in, − money out
  /// How this entry changed the mutual position (net > 0 = they owe you).
  /// Zero for activity that is merely tagged to the contact (their share of a
  /// grocery bill, a recharge) without lending/borrowing/repaying anything.
  final double positionDelta;
  KhataEntry(this.date, this.description, this.amount, {this.positionDelta = 0});
}

const _navy = Color(0xFF141A2A);
const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);

PdfColor _c(Color c) => pdfColorOf(c);

String _money(double v, String currency) {
  final f = NumberFormat.currency(
      locale: 'en_IN', symbol: currency == 'INR' ? 'Rs ' : '$currency ', decimalDigits: 2);
  return f.format(v);
}

String _pdfSafe(String s) => pdfSafe(s);

/// Build the ledger PDF. [net] > 0 means the contact owes the workspace owner;
/// [entries] newest-first; [openDues] outstanding items to highlight.
/// [logoPng] is the app logo (assets/icon.png bytes); omitted in pure tests.
Uint8List buildKhataPdf({
  required String workspaceName,
  required String contactName,
  required double net,
  required List<KhataEntry> entries,
  required List<KhataDueLine> openDues,
  required String currency,
  Uint8List? logoPng,
}) {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 36;
  final page = doc.pages.add();
  final g = page.graphics;
  final w = page.getClientSize().width;

  final h2 = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
  final body = PdfStandardFont(PdfFontFamily.helvetica, 9.5);
  final bodyBold = PdfStandardFont(PdfFontFamily.helvetica, 9.5, style: PdfFontStyle.bold);
  final small = PdfStandardFont(PdfFontFamily.helvetica, 8);
  final dateFmt = DateFormat('dd MMM yyyy');

  var y = drawPdfBrandHeader(
    g,
    width: w,
    subtitle: 'Ledger statement from $workspaceName',
    generatedOn: 'Generated ${dateFmt.format(DateTime.now())}',
    logoPng: logoPng,
  );

  g.drawString(_pdfSafe(contactName), PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      bounds: Rect.fromLTWH(0, y, w, 22));
  y += 22;
  if (entries.isNotEmpty) {
    var oldest = entries.first.date;
    var newest = entries.first.date;
    for (final e in entries) {
      if (e.date.isBefore(oldest)) oldest = e.date;
      if (e.date.isAfter(newest)) newest = e.date;
    }
    g.drawString('Statement period: ${dateFmt.format(oldest)} to ${dateFmt.format(newest)}', small,
        brush: PdfSolidBrush(PdfColor(120, 128, 148)), bounds: Rect.fromLTWH(0, y, w, 12));
    y += 16;
  } else {
    y += 4;
  }

  // Net position banner.
  final owed = net > 0.005;
  final settled = net.abs() <= 0.005;
  g.drawRectangle(
      brush: PdfSolidBrush(settled ? PdfColor(230, 232, 238) : _c(owed ? _green : _red)),
      bounds: Rect.fromLTWH(0, y, w, 30));
  final bannerText = settled
      ? 'All settled. Nothing pending.'
      : owed
          ? 'To receive from $contactName: ${_money(net.abs(), currency)}'
          : 'To pay to $contactName: ${_money(net.abs(), currency)}';
  g.drawString(_pdfSafe(bannerText), h2,
      brush: settled ? PdfSolidBrush(_c(_navy)) : PdfBrushes.white,
      bounds: Rect.fromLTWH(10, y + 8, w - 20, 16));
  y += 42;

  // Sections flow across pages; track where the last layout ended.
  var currentPage = page;

  // Open dues section.
  if (openDues.isNotEmpty) {
    currentPage.graphics.drawString('Outstanding dues', h2, bounds: Rect.fromLTWH(0, y, w, 16));
    y += 20;
    final dueGrid = PdfGrid();
    dueGrid.columns.add(count: 3);
    dueGrid.headers.add(1);
    final dh = dueGrid.headers[0];
    dh.cells[0].value = 'Item';
    dh.cells[1].value = 'Due date';
    dh.cells[2].value = 'Amount';
    for (final d in openDues) {
      final r = dueGrid.rows.add();
      r.cells[0].value = _pdfSafe(d.title);
      r.cells[1].value = dateFmt.format(d.dueDate);
      r.cells[2].value =
          '${_money(d.remaining, currency)} ${d.direction == 'receivable' ? '(to receive)' : '(to pay)'}';
    }
    styleStatementGrid(dueGrid, body: body, bold: bodyBold, rightCols: {2});
    final res = dueGrid.draw(page: currentPage, bounds: Rect.fromLTWH(0, y, w, 0));
    if (res != null) {
      currentPage = res.page;
      y = res.bounds.bottom + 18;
    }
  }

  // Ledger table with the khata balance: the running MUTUAL POSITION (who
  // owes whom), accumulated oldest to newest from each entry's positionDelta,
  // so the newest row's balance equals the net in the banner. Rows that are
  // only tagged activity keep the balance unchanged. The listing is the exact
  // reverse of the accumulation order, so balances read consistently even for
  // several entries on the same date.
  final chronological = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  final display = chronological.reversed.toList();
  final balanceAfter = <double>[];
  var running = 0.0;
  for (final e in chronological) {
    running += e.positionDelta;
    balanceAfter.add(running);
  }
  final grid = PdfGrid();
  grid.columns.add(count: 4);
  grid.headers.add(1);
  final gh = grid.headers[0];
  gh.cells[0].value = 'Date';
  gh.cells[1].value = 'Description';
  gh.cells[2].value = 'Amount';
  gh.cells[3].value = 'Balance';
  grid.columns[0].width = 70;
  grid.columns[2].width = 88;
  grid.columns[3].width = 88;
  for (var i = 0; i < display.length; i++) {
    final e = display[i];
    final bal = balanceAfter[display.length - 1 - i];
    final r = grid.rows.add();
    r.cells[0].value = dateFmt.format(e.date);
    r.cells[1].value = _pdfSafe(e.description);
    r.cells[2].value = '${e.amount >= 0 ? '+' : '-'}${_money(e.amount.abs(), currency)}';
    r.cells[3].value = '${bal >= 0.005 ? '' : (bal <= -0.005 ? '-' : '')}${_money(bal.abs(), currency)}';
  }
  styleStatementGrid(grid, body: body, bold: bodyBold, rightCols: {2, 3});
  currentPage.graphics.drawString('Transactions (${entries.length})', h2, bounds: Rect.fromLTWH(0, y, w, 16));
  grid.draw(page: currentPage, bounds: Rect.fromLTWH(0, y + 20, w, 0));

  drawPdfPageFooters(doc, 'Made with NizKhata | https://nizkhata.web.app');

  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

/// WhatsApp-friendly text summary of the same ledger.
String buildKhataText({
  required String contactName,
  required double net,
  required List<KhataEntry> entries,
  required List<KhataDueLine> openDues,
  required String currency,
  int recent = 5,
}) {
  final dateFmt = DateFormat('dd MMM');
  final b = StringBuffer();
  b.writeln('*Statement of account: $contactName*');
  if (net.abs() <= 0.005) {
    b.writeln('Closing balance: nil. The account is settled.');
  } else if (net > 0) {
    b.writeln('Closing balance receivable: ${_money(net, currency)}');
  } else {
    b.writeln('Closing balance payable: ${_money(net.abs(), currency)}');
  }
  if (openDues.isNotEmpty) {
    b.writeln('\nOpen items:');
    for (final d in openDues) {
      b.writeln('- ${d.title}: ${_money(d.remaining, currency)} (due ${dateFmt.format(d.dueDate)})');
    }
  }
  if (entries.isNotEmpty) {
    b.writeln('\nRecent activity:');
    for (final e in entries.take(recent)) {
      b.writeln(
          '- ${dateFmt.format(e.date)}: ${e.description}, ${e.amount >= 0 ? '+' : '-'}${_money(e.amount.abs(), currency)}');
    }
  }
  b.writeln('\nSent from NizKhata: https://nizkhata.web.app');
  return b.toString();
}

/// Message for an open due, written as a payment notice rather than a chat.
///
/// The amount and the date are set out on their own lines, so the figures can
/// be read at a glance and checked against the other side's own books. Which
/// way the money runs decides which notice it is, and the two are never
/// confused: a receivable is a reminder asking for payment, a payable is a
/// payment advice about money going out. A payable never asks the contact for
/// anything.
String buildDueReminderText({
  required String contactName,
  required String dueTitle,
  required double remaining,
  required DateTime dueDate,
  required String currency,
  required String direction, // payable | receivable
}) {
  final dateFmt = DateFormat('dd MMM yyyy');
  final overdue = dueDate.isBefore(DateTime.now());
  final amount = _money(remaining, currency);
  final when = dateFmt.format(dueDate);
  final b = StringBuffer();
  b.writeln('Hi $contactName,');
  b.writeln();
  b.writeln(direction == 'receivable' ? '*Payment reminder: $dueTitle*' : '*Payment advice: $dueTitle*');
  b.writeln('Amount: $amount');
  b.writeln('Due date: $when${overdue ? ' (overdue)' : ''}');
  b.writeln();
  if (direction == 'receivable') {
    b.writeln(overdue
        ? 'Kindly arrange the payment at the earliest. Please ignore this notice if it has already been settled.'
        : 'Kindly arrange the payment on or before the due date. Please ignore this notice if it has already been settled.');
  } else {
    b.writeln(overdue
        ? 'This payment is pending at my end and will be released shortly. Apologies for the delay.'
        : 'This payment is scheduled and will be released on or before the due date.');
  }
  b.write('\nSent from NizKhata: https://nizkhata.web.app');
  return b.toString();
}
