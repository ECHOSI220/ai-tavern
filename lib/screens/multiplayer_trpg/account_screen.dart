import 'package:flutter/material.dart';

import '../../models/social_models.dart';
import '../../services/trpg/account_client_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({required this.service, super.key});
  final AccountClientService service;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _register = false, _busy = false, _hidePassword = true;
  String? _error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_register ? '注册账号' : '登录账号')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('账号只用于公网联机、好友与云端战役'),
                subtitle: Text(
                  widget.service.usesSupabase
                      ? '使用 Supabase 邮箱账号。AI API Key 不会上传；单机与 Nearby 无需登录。'
                      : 'AI API Key 不会上传；游客仍可使用酒馆、单人和临时局域网房间。',
                ),
              ),
            ),
            TextField(
              controller: _handle,
              enabled: !_busy,
              autocorrect: false,
              keyboardType: widget.service.usesSupabase
                  ? TextInputType.emailAddress
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: widget.service.usesSupabase ? '邮箱' : '唯一用户 ID',
                prefixText: widget.service.usesSupabase ? null : '@',
                hintText: widget.service.usesSupabase
                    ? 'name@example.com'
                    : 'shishu123',
              ),
            ),
            if (_register)
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '昵称（可重复）'),
              ),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: _hidePassword,
              decoration: InputDecoration(
                labelText: '密码（至少 8 位）',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.login),
              label: Text(_register ? '注册并登录' : '登录'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _register = !_register),
              child: Text(_register ? '已有账号？登录' : '没有账号？注册'),
            ),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(title: Text(_error!)),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AuthTokens tokens = _register
          ? await widget.service.register(
              handle: _handle.text,
              displayName: _name.text,
              password: _password.text,
            )
          : await widget.service.login(
              handle: _handle.text,
              password: _password.text,
            );
      if (mounted) Navigator.pop(context, tokens);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _handle.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }
}
