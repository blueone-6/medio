import 'package:flutter/material.dart';

class DesktopShortcutHint {
  const DesktopShortcutHint({
    required this.icon,
    required this.action,
    required this.keys,
    this.detail,
  });

  final IconData icon;
  final String action;
  final String keys;
  final String? detail;
}

const _kSearchShortcut = DesktopShortcutHint(
  icon: Icons.search_rounded,
  action: '打开搜索',
  keys: 'Ctrl+F',
  detail: '搜索电影、剧集与演员',
);

const _kSettingsShortcut = DesktopShortcutHint(
  icon: Icons.settings_outlined,
  action: '打开设置',
  keys: 'Ctrl+,',
  detail: '在首页壳层内切换到设置',
);

const _kRefreshShortcut = DesktopShortcutHint(
  icon: Icons.refresh_rounded,
  action: '刷新首页',
  keys: 'F5',
  detail: '重新拉取续播与推荐',
);

List<DesktopShortcutHint> get kDesktopHomeShortcuts => const <DesktopShortcutHint>[
      _kSearchShortcut,
      _kSettingsShortcut,
      _kRefreshShortcut,
    ];
