import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum VoiceModelKind { asr, tts, vad }

class VoiceModelDescriptor {
  const VoiceModelDescriptor({
    required this.kind,
    required this.id,
    required this.name,
    required this.url,
    required this.requiredFiles,
    this.archive = true,
    this.version = '1',
  });

  final VoiceModelKind kind;
  final String id;
  final String name;
  final Uri url;
  final List<String> requiredFiles;
  final bool archive;
  final String version;
}

class VoiceModelStatus {
  const VoiceModelStatus({required this.installed, required this.bytes});
  final bool installed;
  final int bytes;
}

class VoiceModelManager {
  VoiceModelManager({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _cancelled = <String>{};

  static final senseVoice = VoiceModelDescriptor(
    kind: VoiceModelKind.asr,
    id: 'sensevoice-zh-en-int8-2024-07-17',
    name: 'SenseVoice 中英日韩粤语 INT8',
    url: Uri.parse(
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
      'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2',
    ),
    requiredFiles: const ['model.int8.onnx', 'tokens.txt'],
  );

  static final sileroVad = VoiceModelDescriptor(
    kind: VoiceModelKind.vad,
    id: 'silero-vad',
    name: 'Silero VAD 16kHz',
    url: Uri.parse(
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
      'silero_vad.onnx',
    ),
    requiredFiles: const ['silero_vad.onnx'],
    archive: false,
  );

  static final kokoro = VoiceModelDescriptor(
    kind: VoiceModelKind.tts,
    id: 'kokoro-int8-multi-lang-v1_1',
    name: 'Kokoro 中英多语音色 INT8',
    url: Uri.parse(
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'kokoro-int8-multi-lang-v1_1.tar.bz2',
    ),
    requiredFiles: const ['model.int8.onnx', 'voices.bin', 'tokens.txt'],
  );

  static const all = <VoiceModelDescriptor>[];

  Future<Directory> modelsDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'models'))..createSync(recursive: true);
  }

  Future<Directory> modelDirectory(VoiceModelDescriptor model) async {
    final root = await modelsDirectory();
    final dir = Directory(p.join(root.path, model.kind.name, model.id));
    await dir.create(recursive: true);
    return dir;
  }

  Future<VoiceModelStatus> status(VoiceModelDescriptor model) async {
    final dir = await modelDirectory(model);
    final installed = model.requiredFiles.every(
      (name) => _findFile(dir, name) != null,
    );
    var bytes = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) bytes += await entity.length();
    }
    return VoiceModelStatus(installed: installed, bytes: bytes);
  }

  Future<String?> filePath(VoiceModelDescriptor model, String name) async {
    final dir = await modelDirectory(model);
    return _findFile(dir, name)?.path;
  }

  File? _findFile(Directory root, String name) {
    if (!root.existsSync()) return null;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path) == name) return entity;
    }
    return null;
  }

  Future<void> download(
    VoiceModelDescriptor model, {
    void Function(int received, int? total)? onProgress,
  }) async {
    _cancelled.remove(model.id);
    final dir = await modelDirectory(model);
    final temp = File(p.join(dir.path, '${model.id}.download'));
    final request = http.Request('GET', model.url);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('模型下载失败：HTTP ${response.statusCode}');
    }
    final sink = temp.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (_cancelled.contains(model.id)) {
          throw const HttpException('模型下载已取消');
        }
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, response.contentLength);
      }
    } finally {
      await sink.close();
    }
    if (model.archive) {
      final input = InputFileStream(temp.path);
      final tarFile = File(p.join(dir.path, '${model.id}.tar'));
      final output = OutputFileStream(tarFile.path);
      try {
        BZip2Decoder().decodeStream(input, output);
        await output.close();
        final archive = TarDecoder().decodeStream(
          InputFileStream(tarFile.path),
        );
        await extractArchiveToDisk(archive, dir.path);
      } finally {
        await input.close();
        if (tarFile.existsSync()) await tarFile.delete();
        await temp.delete();
      }
    } else {
      await temp.rename(p.join(dir.path, model.requiredFiles.first));
    }
    final verified = await status(model);
    if (!verified.installed) {
      throw const FileSystemException('模型文件不完整，请重新下载');
    }
    await File(
      p.join(dir.path, 'manifest.json'),
    ).writeAsString(jsonEncode({'id': model.id, 'version': model.version}));
  }

  void cancelDownload(VoiceModelDescriptor model) => _cancelled.add(model.id);

  Future<void> delete(VoiceModelDescriptor model) async {
    final dir = await modelDirectory(model);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  void dispose() => _client.close();
}
