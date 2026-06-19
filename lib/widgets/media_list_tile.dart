import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

double _listTitleLineHeight(BuildContext context) {
  final t = Theme.of(context).textTheme.titleMedium ?? Theme.of(context).textTheme.bodyMedium;
  if (t == null) return 22;
  final fs = t.fontSize ?? 16;
  final h = t.height ?? 1.25;
  return fs * h;
}

class MediaListTile extends StatelessWidget {
  const MediaListTile({
    super.key,
    required this.title,
    this.titleBlock2,
    this.subtitle,
    this.imageUrl,
    this.httpHeaders,
    this.onTap,
    this.showThumbnail = true,
    this.leadingLabel,
  });

  final String title;
  /// 与 [title] 同列展示的第二块（如「第N集.集名」）；两块并存时各一行，否则 [title] 最多两行。
  final String? titleBlock2;
  final String? subtitle;
  final String? imageUrl;
  final Map<String, String>? httpHeaders;
  final VoidCallback? onTap;

  /// When false, shows a compact text row (no poster), suitable for long episode lists.
  final bool showThumbnail;

  /// Shown in place of a thumbnail when [showThumbnail] is false (e.g. episode index).
  final String? leadingLabel;

  @override
  Widget build(BuildContext context) {
    final Widget leading = showThumbnail
        ? ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 48,
              height: 72,
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      httpHeaders: httpHeaders,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.movie),
                    )
                  : const ColoredBox(color: Colors.black26, child: Icon(Icons.movie)),
            ),
          )
        : (leadingLabel != null
            ? CircleAvatar(
                radius: 18,
                child: Text(
                  leadingLabel!,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              )
            : const Icon(Icons.play_circle_outline));

    final lh = _listTitleLineHeight(context);
    const gap = 2.0;
    final titleSlotH = lh * 2 + gap;
    final hasBlock2 = titleBlock2 != null && titleBlock2!.trim().isNotEmpty;
    final titleStyle = Theme.of(context).textTheme.titleMedium ?? Theme.of(context).textTheme.bodyLarge;

    final titleWidget = SizedBox(
      height: titleSlotH,
      width: double.infinity,
      child: hasBlock2
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: lh,
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                ),
                const SizedBox(height: gap),
                SizedBox(
                  height: lh,
                  child: Text(titleBlock2!, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                ),
              ],
            )
          : Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
    );

    return ListTile(
      onTap: onTap,
      dense: !showThumbnail,
      visualDensity: showThumbnail ? null : VisualDensity.compact,
      minVerticalPadding: showThumbnail ? null : 4,
      leading: leading,
      title: titleWidget,
      subtitle: subtitle != null ? Text(subtitle!, maxLines: 2) : null,
    );
  }
}
