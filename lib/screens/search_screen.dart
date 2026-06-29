import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../core/layout/platform_layout.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/media_navigation.dart';
import '../utils/user_facing_error.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/error_view.dart';
import '../widgets/home/home_layout.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_list_tile.dart';
import '../widgets/tv/tv_focus_ring.dart';
import '../widgets/tv/tv_home_layout.dart';
import '../widgets/tv/tv_keyboard_handler.dart';
import '../widgets/tv/tv_text_field.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  var _focused = false;
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty) {
      _controller.text = q;
      _query = q;
    }
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final q = value.trim();
      if (q != _query) {
        setState(() => _query = q);
      }
    });
  }

  void _submitSearch([String? value]) {
    _debounce?.cancel();
    final q = (value ?? _controller.text).trim();
    if (q != _query) {
      setState(() => _query = q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(embySearchProvider(_query));
    final emby = ref.watch(embyServiceProvider);

    if (context.isTvUi) {
      return TvScreenShell(
        title: '搜索',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TvSearchInputRow(
              controller: _controller,
              onSubmit: _submitSearch,
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: _buildTvResults(context, results, emby),
            ),
          ],
        ),
      );
    }

    return _buildDefaultSearch(context, results, emby);
  }

  Widget _buildDefaultSearch(
    BuildContext context,
    AsyncValue<List<dynamic>> results,
    dynamic emby,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HomeLayout.horizontalMargin,
              HomeLayout.searchBarVerticalMargin,
              HomeLayout.horizontalMargin,
              HomeLayout.searchBarVerticalMargin,
            ),
            child: SizedBox(
              height: HomeLayout.searchBarHeight,
              child: Material(
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.pillR,
                  side: BorderSide(
                    color: _focused
                        ? cs.primary.withValues(alpha: 0.55)
                        : cs.outlineVariant.withValues(alpha: 0.45),
                    width: _focused ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: _focused
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: '搜索电影、剧集、演员',
                            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: _submitSearch,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildResultsBody(context, results, emby, tv: false),
          ),
        ],
      ),
    );
  }

  Widget _buildTvResults(
    BuildContext context,
    AsyncValue<List<dynamic>> results,
    dynamic emby,
  ) {
    return _buildResultsBody(context, results, emby, tv: true);
  }

  Widget _buildResultsBody(
    BuildContext context,
    AsyncValue<List<dynamic>> results,
    dynamic emby, {
    required bool tv,
  }) {
    if (_query.isEmpty) {
      return const EmptyStateView(
        icon: Icons.search,
        title: '输入关键字开始搜索',
        subtitle: '可搜索电影、剧集名称',
      );
    }

    return results.when(
      data: (hints) {
        if (hints.isEmpty) {
          return const EmptyStateView(
            icon: Icons.search_off,
            title: '没有找到结果',
            subtitle: '换个关键词试试',
          );
        }
        if (tv) {
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            itemCount: hints.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final m = hints[i].item as EmbyMediaItem;
              final url = emby.posterUrlForItem(m, maxHeight: AppConfig.posterMaxHeight);
              return _TvSearchResultTile(
                title: m.mediaCardSeriesSeasonLine,
                titleBlock2: m.mediaCardEpisodeLine,
                subtitle: m.mediaListSecondaryLine(),
                imageUrl: url,
                httpHeaders: emby.imageAuthHeaders,
                traversalOrder: 10 + i,
                onActivate: () => openSearchMediaItem(context, m),
              );
            },
          );
        }
        return ListView.separated(
          itemCount: hints.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final m = hints[i].item as EmbyMediaItem;
            final url = emby.posterUrlForItem(m, maxHeight: AppConfig.posterMaxHeight);
            return MediaListTile(
              title: m.mediaCardSeriesSeasonLine,
              titleBlock2: m.mediaCardEpisodeLine,
              subtitle: m.mediaListSecondaryLine(),
              imageUrl: url,
              httpHeaders: emby.imageAuthHeaders,
              onTap: () => openSearchMediaItem(context, m),
            );
          },
        );
      },
      loading: () => const LoadingIndicator.list(),
      error: (e, _) {
        if (tv) {
          final cs = Theme.of(context).colorScheme;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: cs.error),
                const SizedBox(height: AppSpacing.md),
                Text(
                  userFacingMessage(e),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(10),
                  child: TvFocusActionButton(
                    label: '重试',
                    icon: Icons.refresh_rounded,
                    autofocus: true,
                    onActivate: () => ref.invalidate(embySearchProvider(_query)),
                  ),
                ),
              ],
            ),
          );
        }
        return ErrorView(
          error: e,
          onRetry: () => ref.invalidate(embySearchProvider(_query)),
        );
      },
    );
  }
}

class _TvSearchInputRow extends StatelessWidget {
  const _TvSearchInputRow({
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final void Function([String? value]) onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TvTextField(
            controller: controller,
            autofocus: true,
            traversalOrder: 1,
            labelText: '关键词',
            hintText: '搜索电影、剧集…',
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmit,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: TvFocusIconButton(
            icon: Icons.search_rounded,
            size: 48,
            iconSize: 24,
            onActivate: () => onSubmit(controller.text),
          ),
        ),
      ],
    );
  }
}

class _TvSearchResultTile extends StatefulWidget {
  const _TvSearchResultTile({
    required this.title,
    this.titleBlock2,
    this.subtitle,
    this.imageUrl,
    this.httpHeaders,
    required this.onActivate,
    this.traversalOrder,
  });

  final String title;
  final String? titleBlock2;
  final String? subtitle;
  final String? imageUrl;
  final Map<String, String>? httpHeaders;
  final VoidCallback onActivate;
  final int? traversalOrder;

  @override
  State<_TvSearchResultTile> createState() => _TvSearchResultTileState();
}

class _TvSearchResultTileState extends State<_TvSearchResultTile> {
  void _onFocusChange(bool focused) {
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: AppMotion.base,
        curve: AppMotion.decelerate,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasBlock2 = widget.titleBlock2 != null && widget.titleBlock2!.trim().isNotEmpty;

    Widget tile = TvFocusRing(
      onActivate: widget.onActivate,
      onFocusChange: _onFocusChange,
      borderRadius: TvHomeLayout.cardRadius,
      scaleFocused: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: AppRadius.smR,
                child: SizedBox(
                  width: 48,
                  height: 72,
                  child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.imageUrl!,
                          httpHeaders: widget.httpHeaders,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: cs.surfaceContainerHighest, child: Icon(Icons.movie, color: cs.onSurfaceVariant)),
                        )
                      : ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.movie, color: cs.onSurfaceVariant),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: hasBlock2 ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                    if (hasBlock2) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.titleBlock2!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium,
                      ),
                    ],
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );

    if (widget.traversalOrder != null) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(widget.traversalOrder!.toDouble()),
        child: tile,
      );
    }
    return tile;
  }
}
