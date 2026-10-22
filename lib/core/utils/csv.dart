/// Builds RFC 4180 CSV text.
///
/// Text cells that a spreadsheet could interpret as a formula (starting with
/// `=`, `+`, `-`, `@`, tab or carriage return) are prefixed with an apostrophe
/// to prevent CSV injection. Numbers, also as text like `-4.60`, stay as-is.
class CsvBuilder {
  CsvBuilder(List<String> header) : _rows = [header];

  final List<List<Object?>> _rows;

  void addRow(List<Object?> cells) => _rows.add(cells);

  int get rowCount => _rows.length - 1;

  /// CSV text with CRLF line endings and a UTF-8 byte order mark so that
  /// spreadsheet applications detect the encoding.
  String build({bool byteOrderMark = true}) {
    final buffer = StringBuffer();
    if (byteOrderMark) buffer.write('﻿');
    for (final row in _rows) {
      buffer
        ..write(row.map(_cell).join(','))
        ..write('\r\n');
    }
    return buffer.toString();
  }

  /// Plain numbers such as `-8.00` cannot be formulas and stay unchanged.
  static final _number = RegExp(r'^-?\d+(\.\d+)?$');

  static String _cell(Object? value) {
    if (value == null) return '';
    if (value is num || value is bool) return value.toString();
    var text = value.toString();
    if (text.isNotEmpty && '=+-@\t\r'.contains(text[0]) && !_number.hasMatch(text)) text = "'$text";
    final needsQuotes = text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r');
    return needsQuotes ? '"${text.replaceAll('"', '""')}"' : text;
  }
}

/// Cents as a plain decimal number for CSV, e.g. `-4.60`.
String centsToDecimal(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
