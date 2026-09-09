import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/chat_attachment.dart';
import '../../models/vision_settings.dart';
import 'vision_provider.dart';

class ImagePreprocessor {
  const ImagePreprocessor();

  static const _uuid = Uuid();
  static const _supportedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  Future<List<ChatAttachment>> pickAndPrepare(VisionSettings settings) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要发送的图片',
      type: FileType.image,
      allowMultiple: true,
      withData: Platform.isAndroid,
    );
    if (result == null || result.files.isEmpty) return const [];
    if (result.files.length > settings.maxImages) {
      throw VisionException('一次最多选择 ${settings.maxImages} 张图片');
    }
    final prepared = <ChatAttachment>[];
    try {
      for (final selected in result.files) {
        prepared.add(await prepareFile(selected, settings));
      }
    } catch (_) {
      for (final attachment in prepared) {
        final file = File(attachment.localPath);
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
    return prepared;
  }

  Future<ChatAttachment> prepareFile(
    PlatformFile selected,
    VisionSettings settings,
  ) async {
    final extension = (selected.extension ?? p.extension(selected.name))
        .replaceFirst('.', '')
        .toLowerCase();
    if (!_supportedExtensions.contains(extension)) {
      throw const VisionException('仅支持 JPG、PNG 和 WebP 图片');
    }
    final sourceBytes =
        selected.bytes ??
        (selected.path == null
            ? null
            : await File(selected.path!).readAsBytes());
    if (sourceBytes == null) throw const VisionException('无法读取所选图片');
    if (sourceBytes.length > settings.maxImageBytes) {
      throw VisionException(
        '图片超过 ${(settings.maxImageBytes / 1024 / 1024).round()} MB 限制',
      );
    }
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) throw const VisionException('图片格式无法解析');

    var processed = decoded;
    if (decoded.width > settings.maxImageDimension ||
        decoded.height > settings.maxImageDimension) {
      if (decoded.width >= decoded.height) {
        processed = img.copyResize(
          decoded,
          width: settings.maxImageDimension,
          interpolation: img.Interpolation.average,
        );
      } else {
        processed = img.copyResize(
          decoded,
          height: settings.maxImageDimension,
          interpolation: img.Interpolation.average,
        );
      }
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'images', 'chat_attachments'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, '${_uuid.v4()}.jpg'));
    final encoded = img.encodeJpg(processed, quality: 84);
    await file.writeAsBytes(encoded, flush: true);
    return ChatAttachment(
      id: _uuid.v4(),
      localPath: file.path,
      mimeType: 'image/jpeg',
      width: processed.width,
      height: processed.height,
      sizeBytes: encoded.length,
    );
  }
}
