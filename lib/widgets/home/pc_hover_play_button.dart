import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import 'glass_surface.dart';
import 'home_layout.dart';

/// PC 海报/横幅悬停播放按钮：淡入 + 缩放，按钮自身 hover 填充主色。
class PcHoverPlayButton extends StatefulWidget {
  const PcHoverPlayButton({
    super.key,
    required this.visible,
    required this.onTap,
    this.size = HomeLayout.pcRecommendPlayButtonSize,
  });

  final bool visible;
  final VoidCallback onTap;
  final double size;

  @override
  State<PcHoverPlayButton> createState() => _PcHoverPlayButtonState();
}

class _PcHoverPlayButtonState extends State<PcHoverPlayButton> {
  var _buttonHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final filled = _buttonHovered;
    final size = widget.size;
    final duration = AppMotion.effectiveDuration(context, AppMotion.slow);
    final motion = AppMotion.animationsEnabled(context);

    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: duration,
      child: AnimatedScale(
        scale: motion ? (widget.visible ? 1 : 0.9) : 1,
        duration: duration,
        child: MouseRegion(
          onEnter: (_) => setState(() => _buttonHovered = true),
          onExit: (_) => setState(() => _buttonHovered = false),
          child: posterPlayControlShell(
            Material(
              color: filled
                  ? colors.playAction
                  : HomeGlassTokens.playControlFill(cs),
              shape: CircleBorder(
                side: BorderSide(color: HomeGlassTokens.playControlBorder(cs)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: filled
                        ? colors.onPlayAction
                        : HomeGlassTokens.playControlIcon(cs, filled: false),
                    size: size * 0.55,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget posterPlayControlShell(Widget child) {
  return ClipOval(child: child);
}
