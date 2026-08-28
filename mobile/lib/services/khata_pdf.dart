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
  final double amount; // signed: + money in (they paid you), − money out
  KhataEntry(this.date, this.description, this.amount);
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
  final small = PdfStandardFont(PdfFontFamily.helvetica, 8);
  final dateFmt = DateFormat('dd MMM yyyy');

  var y = drawPdfBrandHeader(
    g,
    width: w,
    subtitle: 'Ledger statement . $workspaceName',
    generatedOn: 'Generated ${dateFmt.format(DateTime.now())}',
    logoPng: logoPng,
  );

  g.drawString(_pdfSafe(contactName),
      PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      bounds: Rect.fromLTWH(0, y, w, 22));
  y += 26;

  // Net position banner.
  final owed = net > 0.005;
  final settled = net.abs() <= 0.005;
  g.drawRectangle(
      brush: PdfSolidBrush(settled ? PdfColor(230, 232, 238) : _c(owed ? _green : _red)),
      bounds: Rect.fromLTWH(0, y, w, 30));
  final bannerText = settled
      ? 'All settled — no outstanding balance.'
      : owed
          ? 'To receive from $contactName: ${_money(net.abs(), currency)}'
          : 'To pay to $contactName: ${_money(net.abs(), currency)}';
  g.drawString(_pdfSafe(bannerText), h2,
      brush: settled ? PdfSolidBrush(_c(_navy)) : PdfBrushes.white,
      bounds: Rect.fromLTWH(10, y + 8, w - 20, 16));
  y += 42;

  // Sections flow across pages; track where the last layout ended.
  var currentPage = page;

  PdfGridStyle gridStyle() =>
      PdfGridStyle(font: body, cellPadding: PdfPaddings(left: 6, right: 6, top: 4, bottom: 4));

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
    dueGrid.style = gridStyle();
    final res = dueGrid.draw(page: currentPage, bounds: Rect.fromLTWH(0, y, w, 0));
    if (res != null) {
      currentPage = res.page;
      y = res.bounds.bottom + 18;
    }
  }

  // Ledger table — with a khata-style running balance: accumulate oldest to
  // newest, then show each row's balance-after in the newest-first listing.
  final chronological = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  final runningAfter = <KhataEntry, double>{};
  var running = 0.0;
  for (final e in chronological) {
    running += e.amount;
    runningAfter[e] = running;
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
  for (final e in entries) {
    final r = grid.rows.add();
    r.cells[0].value = dateFmt.format(e.date);
    r.cells[1].value = _pdfSafe(e.description);
    r.cells[2].value = '${e.amount >= 0 ? '+' : '-'}${_money(e.amount.abs(), currency)}';
    r.cells[3].value = _money(runningAfter[e] ?? 0, currency);
  }
  grid.style = gridStyle();
  currentPage.graphics
      .drawString('Transactions (${entries.length})', h2, bounds: Rect.fromLTWH(0, y, w, 16));
  grid.draw(page: currentPage, bounds: Rect.fromLTWH(0, y + 20, w, 0));

  // Footer on every page.
  for (var i = 0; i < doc.pages.count; i++) {
    final p = doc.pages[i];
    final size = p.getClientSize();
    p.graphics.drawString(
        'Generated with NizKhata - nizkhata.web.app', small,
        brush: PdfSolidBrush(PdfColor(120, 128, 148)),
        bounds: Rect.fromLTWH(0, size.height - 12, size.width, 12));
  }

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
  b.writeln('*Ledger — $contactName*');
  if (net.abs() <= 0.005) {
    b.writeln('All settled. ✅');
  } else if (net > 0) {
    b.writeln('To receive: ${_money(net, currency)}');
  } else {
    b.writeln('To pay: ${_money(net.abs(), currency)}');
  }
  if (openDues.isNotEmpty) {
    b.writeln('\n*Outstanding:*');
    for (final d in openDues) {
      b.writeln(
          '• ${d.title} — ${_money(d.remaining, currency)} (due ${dateFmt.format(d.dueDate)})');
    }
  }
  if (entries.isNotEmpty) {
    b.writeln('\n*Recent:*');
    for (final e in entries.take(recent)) {
      b.writeln(
          '• ${dateFmt.format(e.date)} ${e.description} — ${e.amount >= 0 ? '+' : '-'}${_money(e.amount.abs(), currency)}');
    }
  }
  b.writeln('\n_Shared via NizKhata_');
  return b.toString();
}

/// Gentle payment-reminder text for an open due.
String buildDueReminderText({
  required String contactName,
  required String dueTitle,
  required double remaining,
  required DateTime dueDate,
  required String currency,
}) {
  final dateFmt = DateFormat('dd MMM yyyy');
  final overdue = dueDate.isBefore(DateTime.now());
  return 'Hi $contactName, a gentle reminder: ${_money(remaining, currency)} '
      'for "$dueTitle" ${overdue ? 'was due on' : 'is due by'} ${dateFmt.format(dueDate)}. '
      'Thank you! 🙏\n\n_Sent via NizKhata_';
}
