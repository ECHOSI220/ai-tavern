import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';

class CardSourceDocument {
  const CardSourceDocument({
    required this.fileName,
    required this.text,
    required this.originalCharacterCount,
    this.truncated = false,
  });

  final String fileName;
  final String text;
  final int originalCharacterCount;
  final bool truncated;
}

class CardSourceDocumentService {
  const CardSourceDocumentService();

  Future<CardSourceDocument?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择制卡资料',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'markdown', 'json', 'docx'],
      allowMultiple: false,
      withData: Platform.isAndroid,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw StateError('无法读取所选文件');
    return extractFromBytes(file.name, bytes);
  }

  CardSourceDocument extractFromBytes(String fileName, List<int> bytes) {
    final extension = fileName.split('.').last.toLowerCase();
    final text = switch (extension) {
      'docx' => _extractDocx(Uint8List.fromList(bytes)),
      'txt' ||
      'md' ||
      'markdown' ||
      'json' => utf8.decode(bytes, allowMalformed: true),
      _ => throw const FormatException('仅支持 TXT、Markdown、JSON 和 DOCX 文件'),
    };
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
        .trim();
    if (normalized.isEmpty) throw const FormatException('文档中没有可读取的文字');

    return CardSourceDocument(
      fileName: fileName,
      text: normalized,
      originalCharacterCount: normalized.length,
      truncated: false,
    );
  }

  String _extractDocx(Uint8List bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw const FormatException('DOCX 文件已损坏或不是有效的 Word 文档');
    }
    ArchiveFile? documentFile;
    for (final entry in archive.files) {
      if (entry.isFile &&
          entry.name.replaceAll('\\', '/') == 'word/document.xml') {
        documentFile = entry;
        break;
      }
    }
    final documentBytes = documentFile?.readBytes();
    if (documentBytes == null) {
      throw const FormatException('DOCX 中找不到正文内容');
    }

    try {
      final xml = XmlDocument.parse(utf8.decode(documentBytes));
      final paragraphs = <String>[];
      for (final paragraph in xml.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'p',
      )) {
        final buffer = StringBuffer();
        for (final node in paragraph.descendants.whereType<XmlElement>()) {
          switch (node.name.local) {
            case 't':
              buffer.write(node.innerText);
            case 'tab':
              buffer.write('\t');
            case 'br':
            case 'cr':
              buffer.write('\n');
          }
        }
        final value = buffer.toString().trimRight();
        if (value.trim().isNotEmpty) paragraphs.add(value);
      }
      return paragraphs.join('\n');
    } catch (_) {
      throw const FormatException('无法解析 DOCX 正文');
    }
  }
}
