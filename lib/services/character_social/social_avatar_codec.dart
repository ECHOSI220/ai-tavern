import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import '../../models/character.dart';

/// A small portable thumbnail, stored only in the account-private card replica.
/// Device paths are never uploaded. The canonical card continues owning its avatar.
class SocialAvatarCodec {
  static Future<Character> materialize(Character card) async {
    final avatar = card.avatar;
    if (avatar == null) return card;
    // Cloud replicas must never resolve an arbitrary local device path.
    if (!avatar.startsWith('data:image/jpeg;base64,')) {
      return card.copyWith(clearAvatar: true);
    }
    final bytes = base64Decode(
      avatar.substring('data:image/jpeg;base64,'.length),
    );
    if (bytes.length > 100000) throw const FormatException('头像缩略图过大');
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/images/avatars');
    await directory.create(recursive: true);
    final file = File('${directory.path}/social-${sha256.convert(bytes)}.jpg');
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    return card.copyWith(avatar: file.path);
  }

  static Future<Map<String, Object?>> encode(Character card) async {
    final result = {...card.toJson(), 'avatar': null};
    final avatar = card.avatar;
    if (avatar == null) return result;
    if (avatar.startsWith('data:image/jpeg;base64,') &&
        avatar.length < 100000) {
      result['avatar'] = avatar;
      return result;
    }
    final file = File(avatar);
    if (!await file.exists() || await file.length() > 10000000) return result;
    final bytes = await file.readAsBytes();
    final thumbnail = await Isolate.run(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return base64Encode(
        img.encodeJpg(img.copyResize(decoded, width: 192), quality: 65),
      );
    });
    if (thumbnail != null && thumbnail.length < 100000) {
      result['avatar'] = 'data:image/jpeg;base64,$thumbnail';
    }
    return result;
  }
}
