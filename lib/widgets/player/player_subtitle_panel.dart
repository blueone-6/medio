import 'package:flutter/material.dart';

/// One selectable subtitle track in the Android player sheet.
@immutable
class PlayerSubtitleOption {
  const PlayerSubtitleOption({
    required this.label,
    required this.onSelected,
    this.detail,
    this.selected = false,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onSelected;
}

/// A visual group of subtitle options.
@immutable
class PlayerSubtitleSection {
  const PlayerSubtitleSection({this.title, required this.options});

  final String? title;
  final List<PlayerSubtitleOption> options;
}

/// Compact centered subtitle sheet used by Android phone playback controls.
///
/// Its dimensions and row rhythm intentionally mirror the Android episode
/// picker: 300-400 logical pixels wide, a 48 logical pixel row height, and a
/// dark rounded panel rather than a full-width Material bottom sheet.
class PlayerSubtitlePanel extends StatelessWidget {
  const PlayerSubtitlePanel({
    super.key,
    required this.onClose,
    required this.sections,
    this.switching = false,
  });

  final VoidCallback onClose;
  final List<PlayerSubtitleSection> sections;
  final bool switching;

  static const double rowHeight = 48;

  int get _optionCount => sections.fold(0, (n, s) => n + s.options.length);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.72).clamp(300.0, 400.0);
    final height = size.height - MediaQuery.paddingOf(context).vertical - 24;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: const Color(0xEE101010),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: true,
          bottom: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '字幕',
                        style: TextStyle(
                          color: Color(0xFFE8E8E8),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                    Text(
                      '$_optionCount 条',
                      style: const TextStyle(
                        color: Color(0x99E8E8E8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onClose,
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.close_rounded,
                            color: Color(0xFFE8E8E8),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              Expanded(
                child: switching
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFFD54F),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: sections.length,
                        itemBuilder: (context, sectionIndex) {
                          final section = sections[sectionIndex];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (section.title != null) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    4,
                                  ),
                                  child: Text(
                                    section.title!,
                                    style: const TextStyle(
                                      color: Color(0x99E8E8E8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                              for (final option in section.options)
                                _PlayerSubtitleOptionRow(option: option),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerSubtitleOptionRow extends StatelessWidget {
  const _PlayerSubtitleOptionRow({required this.option});

  final PlayerSubtitleOption option;

  @override
  Widget build(BuildContext context) {
    final labelColor =
        option.selected ? const Color(0xFFE8E8E8) : const Color(0xCCE8E8E8);

    return Material(
      color: option.selected ? const Color(0x18FFFFFF) : Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x18FFFFFF), width: 1),
          ),
        ),
        child: InkWell(
          onTap: option.onSelected,
          child: SizedBox(
            height: PlayerSubtitlePanel.rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 14,
                        fontWeight:
                            option.selected ? FontWeight.w600 : FontWeight.w400,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (option.detail?.isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 112),
                      child: Text(
                        option.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0x99E8E8E8),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: option.selected
                        ? const Color(0xFFFFD54F)
                        : Colors.transparent,
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
