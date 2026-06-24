import 'dart:async';

import 'package:flutter/material.dart';

/// Top info bar shown over the player while the control chrome is visible.
///
/// Mirrors the bottom control bar's gradient aesthetic (inverted) and shows:
/// - the back button (left),
/// - the title of the currently playing media (middle),
/// - a live wall clock (right).
///
/// The widget is only mounted while the chrome is visible, so the clock timer
/// runs only for the brief chrome-visible window and is cancelled on dispose.
class PlayerTopInfo extends StatefulWidget {
  const PlayerTopInfo({
    super.key,
    required this.title,
    this.onBack,
  });

  /// Title of the currently playing media. Empty hides the title slot.
  final String title;

  /// Invoked when the back button is pressed. When null the button is hidden.
  final VoidCallback? onBack;

  @override
  State<PlayerTopInfo> createState() => _PlayerTopInfoState();
}

class _PlayerTopInfoState extends State<PlayerTopInfo> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = DateTime.now();
      // Only rebuild when the displayed minute changes.
      if (next.minute != _now.minute) {
        setState(() => _now = next);
      } else {
        _now = next;
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  static String _fmtClock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final hasBack = widget.onBack != null;
    final hasTitle = widget.title.isNotEmpty;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xCC0A0A0A),
              Color(0x00121212),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 22),
            child: Row(
              children: [
                if (hasBack)
                  Material(
                    color: const Color(0x99121212),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: widget.onBack,
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFFE8E8E8),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (hasBack && hasTitle) const SizedBox(width: 12),
                if (hasTitle)
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE8E8E8),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 8),
                Text(
                  _fmtClock(_now),
                  style: const TextStyle(
                    color: Color(0xFFE8E8E8),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
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
