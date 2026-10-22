import 'package:coffee_tracker/core/utils/csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes header and rows with CRLF line endings and a BOM', () {
    final csv = CsvBuilder(['a', 'b'])
      ..addRow([1, 'x'])
      ..addRow([null, true]);
    expect(csv.build(), '﻿a,b\r\n1,x\r\n,true\r\n');
    expect(csv.rowCount, 2);
  });

  test('quotes fields with separators, quotes and line breaks', () {
    final csv = CsvBuilder(['text'])
      ..addRow(['one, two'])
      ..addRow(['say "hi"'])
      ..addRow(['line\nbreak']);
    expect(csv.build(byteOrderMark: false), 'text\r\n"one, two"\r\n"say ""hi"""\r\n"line\nbreak"\r\n');
  });

  test('neutralises spreadsheet formulas in text cells', () {
    final csv = CsvBuilder(['name'])
      ..addRow(['=HYPERLINK("evil")'])
      ..addRow(['+1'])
      ..addRow(['@SUM(A1)'])
      ..addRow(['-cmd']);
    final lines = csv.build(byteOrderMark: false).split('\r\n');
    expect(lines[1], '"\'=HYPERLINK(""evil"")"');
    expect(lines[2], "'+1");
    expect(lines[3], "'@SUM(A1)");
    expect(lines[4], "'-cmd");
  });

  test('keeps numbers numeric, including negatives and numeric text', () {
    final csv = CsvBuilder(['n', 'decimal'])..addRow([-460, '-4.60']);
    expect(csv.build(byteOrderMark: false), 'n,decimal\r\n-460,-4.60\r\n');
  });

  test('formats cents as plain decimals', () {
    expect(centsToDecimal(0), '0.00');
    expect(centsToDecimal(5), '0.05');
    expect(centsToDecimal(1275), '12.75');
    expect(centsToDecimal(-460), '-4.60');
  });
}
