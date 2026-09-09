import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ImageStorageService {
  Future<String?> pickAndStoreAvatar() async {
    return pickAndStoreImage(folder: 'avatars');
  }

  Future<String?> pickAndStoreCover() async {
    return pickAndStoreImage(folder: 'covers');
  }

  Future<String?> pickAndStoreImage({required String folder}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: Platform.isAndroid,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    final support = await getApplicationSupportDirectory();
    final safeFolder = folder.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}images'
      '${Platform.pathSeparator}$safeFolder',
    );
    await directory.create(recursive: true);
    final extension = selected.extension?.toLowerCase() ?? 'png';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}${const Uuid().v4()}.$extension',
    );
    if (selected.path case final sourcePath?) {
      await File(sourcePath).copy(destination.path);
    } else if (selected.bytes case final bytes?) {
      await destination.writeAsBytes(bytes, flush: true);
    } else {
      throw StateError('无法读取所选图片');
    }
    return destination.path;
  }
}
