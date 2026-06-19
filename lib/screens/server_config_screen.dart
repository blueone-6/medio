import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/platform_layout.dart';
import '../providers/emby_provider.dart';
import '../providers/home_recommendation_provider.dart';
import '../providers/settings_provider.dart';
import '../core/tv/tv_remote_actions.dart';
import '../widgets/tv/tv_focus_ring.dart';
import '../widgets/tv/tv_home_layout.dart';
import '../widgets/tv/tv_keyboard_handler.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../utils/user_facing_error.dart';
import '../widgets/tv/tv_text_field.dart';

class ServerConfigScreen extends ConsumerStatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  ConsumerState<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends ConsumerState<ServerConfigScreen> {
  final _embyUrl = TextEditingController();
  final _embyUser = TextEditingController();
  final _embyPass = TextEditingController();
  final _embyApiKey = TextEditingController();

  final _urlFocus = FocusNode();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  final _loginFocus = FocusNode();

  bool _busy = false;
  String? _message;
  bool _apiKeyVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(settingsServiceProvider);
      _embyUrl.text = _displayServerUrl(s.embyServerUrl);
      _embyUser.text = s.embyUserName ?? '';
      _embyApiKey.text = s.embyApiKey ?? '';
    });
  }

  /// 已保存 URL 去掉协议前缀，方便 TV 端显示与编辑。
  String _displayServerUrl(String? saved) {
    if (saved == null || saved.isEmpty) return '';
    final uri = Uri.tryParse(saved.trim());
    if (uri == null || uri.host.isEmpty) return saved;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path == '/' ? '' : uri.path;
    return '${uri.host}$port$path';
  }

  @override
  void dispose() {
    _embyUrl.dispose();
    _embyUser.dispose();
    _embyPass.dispose();
    _embyApiKey.dispose();
    _urlFocus.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _loginFocus.dispose();
    super.dispose();
  }

  Future<void> _loginEmby() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final emby = ref.read(embyServiceProvider);
      await emby.authenticate(
        serverUrl: _embyUrl.text.trim(),
        username: _embyUser.text.trim(),
        password: _embyPass.text,
      );
      final s = ref.read(settingsServiceProvider);
      await s.setEmbyApiKey(_embyApiKey.text.trim().isEmpty ? null : _embyApiKey.text.trim());
      if (mounted) {
        ref.invalidate(embyLibrariesProvider);
        ref.invalidate(embyResumeProvider);
        ref.invalidate(embyLatestProvider);
        ref.invalidate(homeRecommendationProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emby 登录成功')),
        );
        context.go('/home');
      }
    } catch (e) {
      setState(() => _message = userFacingMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(settingsServiceProvider).clearEmbySession();
    if (mounted) context.go('/settings/servers');
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTvUi) {
      return _buildTv(context);
    }
    return _buildMobile(context);
  }

  Widget _buildTv(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return TvRemoteActions(
      onBack: () {
        if (context.canPop()) context.pop();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          minimum: const EdgeInsets.all(kTvSafeArea),
          child: TvKeyboardHandler(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '连接 Emby 服务器',
                          style: textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '无需输入 http:// 或 https://，直接填写 IP 或域名即可',
                          style: textTheme.bodyLarge?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),
                        TvTextField(
                          controller: _embyUrl,
                          focusNode: _urlFocus,
                          autofocus: true,
                          traversalOrder: 1,
                          labelText: '服务器地址',
                          hintText: '192.168.1.10',
                          keyboardType: TextInputType.text,
                          onSubmitted: (_) => _userFocus.requestFocus(),
                        ),
                        const SizedBox(height: 20),
                        TvTextField(
                          controller: _embyUser,
                          focusNode: _userFocus,
                          traversalOrder: 2,
                          labelText: '用户名',
                          onSubmitted: (_) => _passFocus.requestFocus(),
                        ),
                        const SizedBox(height: 20),
                        TvTextField(
                          controller: _embyPass,
                          focusNode: _passFocus,
                          traversalOrder: 3,
                          labelText: '密码',
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_busy) _loginEmby();
                          },
                        ),
                        const SizedBox(height: 32),
                        if (_busy)
                          const Center(child: CircularProgressIndicator())
                        else
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(4),
                            child: TvFocusRing(
                              focusNode: _loginFocus,
                              onActivate: _loginEmby,
                              borderRadius: TvHomeLayout.cardRadius,
                              child: Material(
                                color: cs.primary,
                                borderRadius:
                                    BorderRadius.circular(TvHomeLayout.cardRadius),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  child: Text(
                                    '连接并登录',
                                    style: textTheme.titleMedium?.copyWith(
                                      color: cs.onPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_message != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            _message!,
                            style: textTheme.bodyLarge?.copyWith(color: cs.error),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器配置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Emby', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _embyUrl,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '192.168.1.10（无需 http://，将自动尝试 https 与 http）',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _embyUser,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _embyPass,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _embyApiKey,
              obscureText: !_apiKeyVisible,
              decoration: InputDecoration(
                labelText: 'API Key（可选，优先于会话）',
                suffixIcon: IconButton(
                  icon: Icon(_apiKeyVisible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _busy ? null : _loginEmby,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录并保存'),
            ),
            TextButton(onPressed: _logout, child: const Text('清除 Emby 会话')),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appColors.danger,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
