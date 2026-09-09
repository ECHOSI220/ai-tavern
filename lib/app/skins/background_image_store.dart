import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Theme images never touch avatars, campaign images or attachments.
class BackgroundImageStore {
  static const maxEncodedBytes = 24 * 1024 * 1024;
  static const maxEdge = 1920;
  Future<String?> pickAndStore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final item = result.files.single;
    if (item.size > maxEncodedBytes) {
      throw const FormatException('图片超过 24 MB，请先压缩后再选择。');
    }
    final bytes = item.path != null
        ? await File(item.path!).readAsBytes()
        : item.bytes;
    if (bytes == null) throw const FormatException('无法读取所选图片。');
    final resized = await normalize(bytes);
    final support = await getApplicationSupportDirectory();
    final directory = await Directory(
      '${support.path}${Platform.pathSeparator}skin_backgrounds',
    ).create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${const Uuid().v4()}.png',
    );
    await file.writeAsBytes(resized, flush: true);
    return file.path;
  }

  static Future<Uint8List> normalize(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxEncodedBytes) {
      throw const FormatException('图片为空或超过 24 MB。');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      // Inspect dimensions before allocating a full-resolution raster.
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > 100000000) {
        throw const FormatException('图片尺寸过大，请先缩小到 10000 像素以内。');
      }
      final scale = math.min(
        1.0,
        maxEdge / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      final data = await decoded.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('无法转换图片格式。');
      return data.buffer.asUint8List();
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
