import 'dart:convert';

import 'package:ai_tavern/services/card_source_document_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CardSourceDocumentService();

  test('读取 UTF-8 文本资料', () {
    final document = service.extractFromBytes(
      'idea.md',
      utf8.encode('# 世界观\n漂浮城市依靠龙晶运转。'),
    );

    expect(document.fileName, 'idea.md');
    expect(document.text, contains('漂浮城市'));
    expect(document.truncated, isFalse);
  });

  test('从 DOCX 正文按段提取文字', () {
    const documentXml = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>第一章：雾港</w:t></w:r></w:p>
    <w:p><w:r><w:t>少女在钟声中醒来。</w:t></w:r></w:p>
  </w:body>
</w:document>''';
    final archive = Archive()
      ..addFile(ArchiveFile.string('word/document.xml', documentXml));
    final bytes = ZipEncoder().encode(archive);

    final document = service.extractFromBytes('story.docx', bytes);

    expect(document.text, '第一章：雾港\n少女在钟声中醒来。');
  });

  test('拒绝没有正文的伪 DOCX', () {
    final archive = Archive()..addFile(ArchiveFile.string('fake.txt', 'no'));
    final bytes = ZipEncoder().encode(archive);

    expect(
      () => service.extractFromBytes('broken.docx', bytes),
      throwsFormatException,
    );
  });

  test('超大文本完整保留而不截断', () {
    final source = List.filled(310000, '界').join();
    final document = service.extractFromBytes('large.txt', utf8.encode(source));

    expect(document.originalCharacterCount, 310000);
    expect(document.text.length, 310000);
    expect(document.truncated, isFalse);
  });
}
