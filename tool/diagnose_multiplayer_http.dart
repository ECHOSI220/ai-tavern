import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../lib/services/ai/system_proxy_client.dart';

Future<void> main() async {
  final config = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final key = config['key'] as String;
  for (final test in config['tests'] as List) {
    final client = SystemProxyClient(resolveWindowsProxy);
    final watch = Stopwatch()..start();
    try {
      final request = http.Request('POST', Uri.parse('https://api.deepseek.com/chat/completions'))
        ..headers.addAll({'Content-Type':'application/json','Accept':'application/json','Authorization':'Bearer $key'})
        ..body = jsonEncode(test['body']);
      stdout.writeln(jsonEncode({'test':test['name'],'bytes':request.bodyBytes.length,'stage':'send'}));
      final response = await client.send(request).timeout(const Duration(seconds: 35));
      stdout.writeln(jsonEncode({'test':test['name'],'status':response.statusCode,'ms':watch.elapsedMilliseconds}));
      final body = await response.stream.bytesToString().timeout(const Duration(seconds: 35));
      final decoded = jsonDecode(body) as Map;
      stdout.writeln(jsonEncode({'test':test['name'],'choices':(decoded['choices'] as List?)?.length,'error':decoded['error'] is Map ? (decoded['error'] as Map)['type'] : null,'ms':watch.elapsedMilliseconds}));
      final choices = decoded['choices'] as List? ?? [];
      if (choices.isNotEmpty) {
        final message = choices.first['message'] as Map;
        final calls = message['tool_calls'] as List? ?? [];
        stdout.writeln(jsonEncode({'toolCalls':calls.length,'finalChars':(message['content'] as String? ?? '').length,'finishReason':choices.first['finish_reason']}));
        if (calls.isNotEmpty) {
          final follow = Map<String,dynamic>.from(test['body'] as Map);
          follow['messages'] = [...follow['messages'] as List, message,
            for (final call in calls) {'role':'tool','tool_call_id':call['id'],'content':'{"accepted":true,"minutes":5}'}];
          follow['tool_choice'] = 'none';
          final reply = await client.post(Uri.parse('https://api.deepseek.com/chat/completions'), headers:{'Content-Type':'application/json','Authorization':'Bearer $key'}, body:jsonEncode(follow)).timeout(const Duration(seconds:35));
          final finalJson = jsonDecode(reply.body) as Map;
          final finalChoices = finalJson['choices'] as List? ?? [];
          stdout.writeln(jsonEncode({'stage':'tool_continuation','status':reply.statusCode,'finalChars':finalChoices.isEmpty ? 0 : (finalChoices.first['message']['content'] as String? ?? '').length}));
        }
      }
    } catch (e) {
      stdout.writeln(jsonEncode({'test':test['name'],'exception':e.runtimeType.toString(),'detail':e.toString().replaceAll(key,'[redacted]'),'ms':watch.elapsedMilliseconds}));
    } finally { client.close(); }
  }
}
