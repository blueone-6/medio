import 'package:flutter/material.dart';

/// One row in a [PlayerMenuSheet]. A row is either a section header
/// ([sectionTitle] != null), a leaf action ([onTap]), or a submenu entry
/// ([children] != null) that pushes a nested page inside the sheet.
@immutable
class PlayerMenuRow {
  const PlayerMenuRow({
    this.label,
    this.value,
    this.selected = false,
    this.onTap,
    this.children,
    this.sectionTitle,
  });

  /// Required for regular rows; omitted when [sectionTitle] is set.
  final String? label;
  final String? value;
  final bool selected;
  final VoidCallback? onTap;
  final List<PlayerMenuRow>? children;
  final String? sectionTitle;
}

class _PlayerMenuPage {
  const _PlayerMenuPage({required this.title, this.countText, required this.rows});

  final String title;
  final String? countText;
  final List<PlayerMenuRow> rows;
}

/// Centered dark rounded menu sheet used by the mobile player controls.
///
/// Its dimensions and row rhythm intentionally mirror the Android subtitle
/// picker: 300-400 logical pixels wide, a 48 logical pixel row height, and a
/// dark rounded panel rather than a full-width Material bottom sheet.
/// Rows with [PlayerMenuRow.children] push a nested page inside the same
/// panel (with a slide transition); the header shows a back arrow then.
class PlayerMenuSheet extends StatefulWidget {
  const PlayerMenuSheet({
    super.key,
    required this.title,
    required this.rows,
    this.countText,
  });

  final String title;
  final String? countText;
  final List<PlayerMenuRow> rows;

  static const double rowHeight = 48;

  @override
  State<PlayerMenuSheet> createState() => _PlayerMenuSheetState();
}

class _PlayerMenuSheetState extends State<PlayerMenuSheet> {
  final List<_PlayerMenuPage> _stack = [];
  bool _animatingForward = true;

  @override
  void initState() {
    super.initState();
    _stack.add(_PlayerMenuPage(
      title: widget.title,
      countText: widget.countText,
      rows: widget.rows,
    ));
  }

  _PlayerMenuPage get _page => _stack.last;

  void _push(List<PlayerMenuRow> rows, String title, String? countText) {
    setState(() {
      _animatingForward = true;
      _stack.add(_PlayerMenuPage(title: title, countText: countText, rows: rows));
    });
  }

  void _pop() {
    if (_stack.length <= 1) return;
    setState(() {
      _animatingForward = false;
      _stack.removeLast();
    });
  }

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
              _buildHeader(),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    final begin = _animatingForward
                        ? const Offset(0.08, 0)
                        : const Offset(-0.08, 0);
                    return SlideTransition(
                      position: Tween<Offset>(begin: begin, end: Offset.zero)
                          .animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: ListView.builder(
                    key: ValueKey<int>(_stack.length),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _page.rows.length,
                    itemBuilder: (context, index) =>
                        _buildRow(_page.rows[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final canPop = _stack.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: canPop
                ? Material(
                    color: const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _pop,
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: Color(0xFFE8E8E8),
                          size: 20,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Text(
              _page.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE8E8E8),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          if (_page.countText != null)
            Text(
              _page.countText!,
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
              onTap: () => Navigator.maybePop(context),
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
    );
  }

  Widget _buildRow(PlayerMenuRow row) {
    if (row.sectionTitle != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          row.sectionTitle!,
          style: const TextStyle(
            color: Color(0x99E8E8E8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      );
    }

    final label = row.label ?? '';
    final hasChildren = row.children != null && row.children!.isNotEmpty;
    final labelColor =
        row.selected ? const Color(0xFFE8E8E8) : const Color(0xCCE8E8E8);

    return Material(
      color: row.selected ? const Color(0x18FFFFFF) : Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x18FFFFFF), width: 1),
          ),
        ),
        child: InkWell(
          onTap: () {
            if (hasChildren) {
              _push(row.children!, row.label ?? '', null);
            } else {
              row.onTap?.call();
            }
          },
          child: SizedBox(
            height: PlayerMenuSheet.rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 14,
                        fontWeight:
                            row.selected ? FontWeight.w600 : FontWeight.w400,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (row.value != null) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 112),
                      child: Text(
                        row.value!,
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
                  if (hasChildren)
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Color(0x66FFFFFF),
                    )
                  else
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: row.selected
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
