import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OpenSearchIntent extends Intent {
  const OpenSearchIntent();
}

class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.child,
    this.onSearch,
    this.onSettings,
    this.onRefresh,
  });

  final Widget child;
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          const OpenSearchIntent(),
      const SingleActivator(LogicalKeyboardKey.comma, control: true):
          const OpenSettingsIntent(),
      const SingleActivator(LogicalKeyboardKey.f5): const RefreshIntent(),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenSearchIntent: CallbackAction<OpenSearchIntent>(
            onInvoke: (_) {
              onSearch?.call();
              return null;
            },
          ),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (_) {
              onSettings?.call();
              return null;
            },
          ),
          RefreshIntent: CallbackAction<RefreshIntent>(
            onInvoke: (_) {
              onRefresh?.call();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
