import '../../models/api_profile.dart';

class AiTestResult {
  const AiTestResult({required this.response, this.model});

  final String response;
  final String? model;
}

class AiException implements Exception {
  const AiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => statusCode == null ? message : '$statusCode: $message';
}

abstract interface class AiProvider {
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  });

  Future<AiTestResult> testConnection({
    required ApiProfile profile,
    required String apiKey,
  });

  void cancel();
}
