import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/api_profile.dart';
import '../../repositories/api_repository.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai_service.dart';

class ApiProfileEditorScreen extends StatefulWidget {
  const ApiProfileEditorScreen({
    required this.repository,
    required this.aiService,
    this.initialProfile,
    super.key,
  });

  final ApiRepository repository;
  final AiService aiService;
  final ApiProfile? initialProfile;

  @override
  State<ApiProfileEditorScreen> createState() => _ApiProfileEditorScreenState();
}

class _ApiProfileEditorScreenState extends State<ApiProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _temperature;
  late final TextEditingController _topP;
  late final TextEditingController _maxTokens;
  late final TextEditingController _timeout;
  late final TextEditingController _headers;
  var _stream = true;
  var _showKey = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _name = TextEditingController(text: profile?.name);
    _baseUrl = TextEditingController(text: profile?.baseUrl);
    _apiKey = TextEditingController();
    _model = TextEditingController(text: profile?.model);
    _temperature = TextEditingController(
      text: '${profile?.temperature ?? 0.9}',
    );
    _topP = TextEditingController(text: '${profile?.topP ?? 1.0}');
    _maxTokens = TextEditingController(text: '${profile?.maxTokens ?? 2000}');
    _timeout = TextEditingController(text: '${profile?.timeoutSeconds ?? 60}');
    _headers = TextEditingController(
      text: const JsonEncoder.withIndent(
        '  ',
      ).convert(profile?.extraHeaders ?? const <String, String>{}),
    );
    _stream = profile?.stream ?? true;
    if (profile != null) _loadKey(profile.id);
  }

  Future<void> _loadKey(String id) async {
    final key = await widget.repository.readApiKey(id);
    if (mounted) _apiKey.text = key;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _baseUrl,
      _apiKey,
      _model,
      _temperature,
      _topP,
      _maxTokens,
      _timeout,
      _headers,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> _parseHeaders() {
    final source = _headers.text.trim();
    if (source.isEmpty) return const {};
    final value = jsonDecode(source);
    if (value is! Map) throw const FormatException('额外 Header 必须是 JSON 对象');
    return value.map((key, value) => MapEntry('$key', '$value'));
  }

  ApiProfile? _buildProfile({bool showError = true}) {
    if (!_formKey.currentState!.validate()) return null;
    try {
      return ApiProfile(
        id: widget.initialProfile?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        temperature: double.tryParse(_temperature.text.trim()) ?? 0.9,
        topP: double.tryParse(_topP.text.trim()) ?? 1,
        maxTokens: int.tryParse(_maxTokens.text.trim()) ?? 2000,
        stream: _stream,
        timeoutSeconds: int.tryParse(_timeout.text.trim()) ?? 60,
        extraHeaders: _parseHeaders(),
      );
    } catch (error) {
      if (showError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('配置无效：$error')));
      }
      return null;
    }
  }

  Future<void> _save() async {
    final profile = _buildProfile();
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.upsert(profile, apiKey: _apiKey.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存 API 配置失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    final profile = _buildProfile();
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.aiService.testConnection(
        profile: profile,
        apiKey: _apiKey.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('✓ API 连接成功'),
          content: SelectableText(
            '模型：${result.model ?? profile.model}\n\n响应：${result.response}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } on AiException catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('API 连接失败'),
          content: SelectableText(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('测试失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool secret = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      obscureText: secret && !_showKey,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        suffixIcon: secret
            ? IconButton(
                onPressed: () => setState(() => _showKey = !_showKey),
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              )
            : null,
      ),
      validator: required
          ? (value) =>
                value == null || value.trim().isEmpty ? '请输入$label' : null
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialProfile == null ? '新建 API 配置' : '编辑 API 配置'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _field(_name, '配置名称', required: true),
            _field(
              _baseUrl,
              'API 地址',
              required: true,
              helper: '例如 https://example.com/v1',
            ),
            _field(_apiKey, 'API Key', secret: true),
            _field(_model, '模型', required: true),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _temperature,
                    'Temperature',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _topP,
                    'Top P',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _maxTokens,
                    '最大输出 Tokens',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _timeout,
                    '超时（秒）',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Streaming 流式输出'),
              value: _stream,
              onChanged: (value) => setState(() => _stream = value),
            ),
            _field(
              _headers,
              '额外 Headers（JSON）',
              maxLines: 6,
              helper: 'API Key 不要写在这里',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: const Icon(Icons.network_check),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('测试连接'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('保存 API 配置'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
