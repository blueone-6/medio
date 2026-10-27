import 'package:flutter/material.dart';

/// Offset control used by the player menus for subtitle and A/V sync.
///
/// The current offset sits in the middle, flanked by a fine (±0.1 s) and a
/// coarse (±0.5 s) step button on each side. The centre value doubles as the
/// reset action, so a menu does not need a separate "重置同步" row.
///
/// Steps that would leave [minMs]–[maxMs] are disabled instead of being clamped
/// silently, which keeps the control honest at the range ends (e.g. native
/// subtitle cues, which can only be delayed and therefore pass `minMs: 0`).
class OffsetStepper extends StatelessWidget {
  const OffsetStepper({
    super.key,
    required this.valueMs,
    required this.onAdjust,
    required this.onReset,
    this.minMs = -30000,
    this.maxMs = 30000,
    this.zeroLabel = '已对齐',
  });

  /// Alignment with the dark menu sheets the two player controls use.
  static const _foreground = Color(0xFFE8E8E8);
  static const _foregroundDisabled = Color(0x4DE8E8E8);
  static const _foregroundHint = Color(0x99E8E8E8);
  static const _buttonFill = Color(0x1AFFFFFF);

  static const fineStepMs = 100;
  static const coarseStepMs = 500;
  static const _buttonWidth = 44.0;
  static const _valueMinWidth = 84.0;

  final int valueMs;
  final void Function(int deltaMs) onAdjust;
  final VoidCallback onReset;
  final int minMs;
  final int maxMs;

  /// Hint under the value when it is zero: '已对齐' for A/V sync, '无偏移' for
  /// subtitles.
  final String zeroLabel;

  /// `+0.3s` / `-0.1s` / `0.0s`, one decimal.
  String get valueLabel {
    if (valueMs == 0) return '0.0s';
    final seconds = (valueMs.abs() / 1000.0).toStringAsFixed(1);
    return '${valueMs > 0 ? '+' : '-'}${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        // A centered cluster rather than edge-to-edge buttons: the offset reads
        // as one control instead of five items floating in an empty row.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepButton('-0.5', -coarseStepMs),
              const SizedBox(width: 5),
              _stepButton('-0.1', -fineStepMs),
              const SizedBox(width: 8),
              _valuePill(),
              const SizedBox(width: 8),
              _stepButton('+0.1', fineStepMs),
              const SizedBox(width: 5),
              _stepButton('+0.5', coarseStepMs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepButton(String label, int deltaMs) {
    final next = valueMs + deltaMs;
    final enabled = next >= minMs && next <= maxMs;
    final isLater = deltaMs > 0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: isLater ? '延后 $label 秒' : '提前 ${label.substring(1)} 秒',
      child: SizedBox(
        width: _buttonWidth,
        height: 34,
        child: Material(
          color: _buttonFill,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? () => onAdjust(deltaMs) : null,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? _foreground : _foregroundDisabled,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _valuePill() {
    return Semantics(
      button: valueMs != 0,
      label: '当前偏移 $valueLabel，点按归零',
      child: SizedBox(
        height: 40,
        child: Material(
          color: _buttonFill,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: valueMs == 0 ? null : onReset,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: _valueMinWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      valueLabel,
                      maxLines: 1,
                      style: const TextStyle(
                        color: _foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      valueMs == 0 ? zeroLabel : '点此归零',
                      maxLines: 1,
                      style: const TextStyle(
                        color: _foregroundHint,
                        fontSize: 10,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
