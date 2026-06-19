import 'package:flutter/material.dart';

import '../../core/layout/platform_layout.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../models/emby/emby_library.dart';
import '../home/home_layout.dart';
import '../home/home_typography.dart';
import '../tv/tv_focus_ring.dart';

/// Top-level Emby library switcher when [libraries.length] > 1.
class LibraryRootPicker extends StatelessWidget {
  const LibraryRootPicker({
    super.key,
    required this.libraries,
    required this.selectedId,
    required this.onSelected,
    this.padding,
    this.tv = false,
  });

  final List<EmbyLibrary> libraries;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry? padding;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    if (libraries.length <= 1) return const SizedBox.shrink();

    final resolvedPadding =
        padding ?? const EdgeInsets.only(bottom: AppSpacing.md);

    if (tv || context.isTvUi) {
      return Padding(
        padding: resolvedPadding,
        child: _TvLibraryChips(
          libraries: libraries,
          selectedId: selectedId,
          onSelected: onSelected,
        ),
      );
    }

    return Padding(
      padding: resolvedPadding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: _TouchLibraryDropdown(
          libraries: libraries,
          selectedId: selectedId,
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class LibraryRootChipPicker extends StatelessWidget {
  const LibraryRootChipPicker({
    super.key,
    required this.libraries,
    required this.selectedId,
    required this.onSelected,
    this.padding,
  });

  final List<EmbyLibrary> libraries;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry? padding;

  static const _chipHeight = 34.0;
  static const _moreWidth = 56.0;
  static const _maxChipWidth = 132.0;
  static const _minChipWidth = 38.0;
  static const _estimatedChipHorizontalPadding = 20.0;
  static const _estimatedTextWidth = 13.0;

  @override
  Widget build(BuildContext context) {
    if (libraries.length <= 1) return const SizedBox.shrink();
    final resolvedPadding =
        padding ?? const EdgeInsets.only(bottom: AppSpacing.md);

    return Padding(
      padding: resolvedPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final visible = _visibleLibraries(constraints.maxWidth);
          final overflow = visible.length < libraries.length;
          return SizedBox(
            height: _chipHeight,
            child: Row(
              children: [
                Expanded(
                  child: ClipRect(
                    child: Row(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0) const SizedBox(width: AppSpacing.sm),
                          _LibraryChipButton(
                            label: visible[i].name,
                            width: _estimatedChipWidth(visible[i].name),
                            selected: visible[i].id == selectedId,
                            underlineKey: ValueKey(
                              'library-tab-underline-${visible[i].id}',
                            ),
                            onPressed: () => onSelected(visible[i].id),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (overflow) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _LibraryMoreButton(
                    onPressed: () => _showAllCategories(context),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  List<EmbyLibrary> _visibleLibraries(double maxWidth) {
    final available = maxWidth.isFinite ? maxWidth : 0;
    final selected = libraries.firstWhere(
      (lib) => lib.id == selectedId,
      orElse: () => libraries.first,
    );
    if (available <= 0) return [selected];

    final selectedWidth = _estimatedChipWidth(selected.name);
    final rowLimit =
        (available - AppSpacing.sm - _moreWidth).clamp(0.0, available);
    if (selectedWidth >= rowLimit) return [selected];

    var used = 0.0;
    final visible = <EmbyLibrary>[];
    for (final lib in libraries) {
      final nextWidth = _estimatedChipWidth(lib.name);
      final spacing = visible.isEmpty ? 0.0 : AppSpacing.sm;
      if (used + spacing + nextWidth > rowLimit) break;
      used += spacing + nextWidth;
      visible.add(lib);
    }

    if (!visible.any((lib) => lib.id == selected.id)) {
      while (visible.isNotEmpty) {
        final currentWidth = visible.fold<double>(
              0,
              (sum, lib) => sum + _estimatedChipWidth(lib.name),
            ) +
            AppSpacing.sm * (visible.length - 1);
        const selectedSpacing = AppSpacing.sm;
        if (currentWidth + selectedSpacing + selectedWidth <= rowLimit) break;
        visible.removeLast();
      }
      visible.add(selected);
      visible.sort(
        (a, b) => libraries.indexOf(a).compareTo(libraries.indexOf(b)),
      );
    }

    return visible.isEmpty ? [selected] : visible;
  }

  double _estimatedChipWidth(String label) {
    final width = (label.characters.length * _estimatedTextWidth) +
        _estimatedChipHorizontalPadding;
    return width.clamp(_minChipWidth, _maxChipWidth);
  }

  Future<void> _showAllCategories(BuildContext context) async {
    final selected = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: AppMotion.effectiveDuration(context, AppMotion.base),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.topCenter,
          child: _LibraryCategorySheet(
            libraries: libraries,
            selectedId: selectedId,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.decelerate,
          reverseCurve: AppMotion.accelerate,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
    if (selected != null) onSelected(selected);
  }
}

class _LibraryChipButton extends StatelessWidget {
  const _LibraryChipButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.width,
    this.pill = false,
    this.underlineKey,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final double? width;
  final bool pill;
  final Key? underlineKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.primary : cs.onSurfaceVariant;

    if (pill) {
      final bg = selected
          ? cs.primaryContainer.withValues(alpha: 0.34)
          : cs.surfaceContainerHigh.withValues(alpha: 0.78);
      final border = selected
          ? cs.primary.withValues(alpha: 0.45)
          : cs.outlineVariant.withValues(alpha: 0.45);
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: LibraryRootChipPicker._minChipWidth,
          maxWidth: LibraryRootChipPicker._maxChipWidth,
        ),
        child: SizedBox(
          width: width,
          height: LibraryRootChipPicker._chipHeight,
          child: Material(
            color: bg,
            borderRadius: AppRadius.pillR,
            child: InkWell(
              onTap: onPressed,
              borderRadius: AppRadius.pillR,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.pillR,
                  border: Border.all(color: border),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardMeta(context).copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
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

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: LibraryRootChipPicker._minChipWidth,
        maxWidth: LibraryRootChipPicker._maxChipWidth,
      ),
      child: SizedBox(
        width: width,
        height: LibraryRootChipPicker._chipHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: AppRadius.smR,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.cardMeta(context).copyWith(
                                color: fg,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AnimatedContainer(
                              key: selected ? underlineKey : null,
                              duration: AppMotion.fast,
                              curve: AppMotion.standard,
                              height: HomeLayout.filterUnderlineThickness,
                              width: selected ? double.infinity : 0,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: AppRadius.pillR,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: HomeLayout.filterUnderlineThickness,
                    child: selected ? null : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryMoreButton extends StatelessWidget {
  const _LibraryMoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '展开全部分类',
      child: SizedBox(
        width: LibraryRootChipPicker._moreWidth,
        height: LibraryRootChipPicker._chipHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: AppRadius.smR,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '更多',
                  style: AppTextStyles.cardMeta(context).copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryCategorySheet extends StatelessWidget {
  const _LibraryCategorySheet({
    required this.libraries,
    required this.selectedId,
  });

  final List<EmbyLibrary> libraries;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Material(
        color: cs.surfaceContainer,
        elevation: 6,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.lg),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width < 760 ? width : 720,
            minWidth: width < 360 ? width : 320,
            maxHeight: MediaQuery.sizeOf(context).height * 0.42,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择分类',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭分类面板',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final lib in libraries)
                          _LibraryChipButton(
                            label: lib.name,
                            selected: lib.id == selectedId,
                            pill: true,
                            onPressed: () => Navigator.of(context).pop(lib.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TouchLibraryDropdown extends StatelessWidget {
  const _TouchLibraryDropdown({
    required this.libraries,
    required this.selectedId,
    required this.onSelected,
  });

  final List<EmbyLibrary> libraries;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = libraries.firstWhere((l) => l.id == selectedId,
        orElse: () => libraries.first);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadius.smR,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: current.id,
            isDense: true,
            borderRadius: AppRadius.smR,
            style: AppTextStyles.cardMeta(context),
            icon: Icon(Icons.unfold_more_rounded,
                size: 18, color: cs.onSurfaceVariant),
            items: [
              for (final lib in libraries)
                DropdownMenuItem(
                  value: lib.id,
                  child: Text(lib.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              if (id != null) onSelected(id);
            },
          ),
        ),
      ),
    );
  }
}

class _TvLibraryChips extends StatelessWidget {
  const _TvLibraryChips({
    required this.libraries,
    required this.selectedId,
    required this.onSelected,
  });

  final List<EmbyLibrary> libraries;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < libraries.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              _TvLibraryChip(
                label: libraries[i].name,
                selected: libraries[i].id == selectedId,
                onActivate: () => onSelected(libraries[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TvLibraryChip extends StatefulWidget {
  const _TvLibraryChip({
    required this.label,
    required this.selected,
    required this.onActivate,
  });

  final String label;
  final bool selected;
  final VoidCallback onActivate;

  @override
  State<_TvLibraryChip> createState() => _TvLibraryChipState();
}

class _TvLibraryChipState extends State<_TvLibraryChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final focused = _focused;
    final selected = widget.selected;

    final Color bg;
    final Color fg;
    final Border? border;

    if (focused) {
      bg = cs.primary;
      fg = cs.onPrimary;
      border = null;
    } else if (selected) {
      bg = cs.primaryContainer.withValues(alpha: 0.32);
      fg = cs.primary;
      border = Border.all(color: cs.primary.withValues(alpha: 0.45));
    } else {
      bg = Colors.transparent;
      fg = cs.onSurfaceVariant;
      border = Border.all(color: cs.outlineVariant.withValues(alpha: 0.35));
    }

    return TvFocusRing(
      onActivate: widget.onActivate,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: AppRadius.sm,
      scaleFocused: false,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.smR,
          border: border,
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: HomeTypography.labelSm(fg).copyWith(
            fontWeight: selected || focused ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
