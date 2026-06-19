import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_motion.dart';
import '../../core/tv/tv_remote_actions.dart';
import 'tv_home_layout.dart';



/// Stitch `.tv-focus-ring` — scale + outline on D-Pad focus.

class TvFocusRing extends StatefulWidget {

  const TvFocusRing({

    super.key,

    required this.child,

    this.onActivate,

    this.autofocus = false,

    this.focusNode,

    this.onFocusChange,

    this.borderRadius = TvHomeLayout.cardRadius,

    this.scaleFocused = true,

    this.showBorder = true,

    this.borderWidth = TvHomeLayout.focusBorderWidth,

  });



  final Widget child;

  final VoidCallback? onActivate;

  final bool autofocus;

  final FocusNode? focusNode;

  final ValueChanged<bool>? onFocusChange;

  final double borderRadius;

  final bool scaleFocused;

  final bool showBorder;

  final double borderWidth;



  @override

  State<TvFocusRing> createState() => _TvFocusRingState();

}



class _TvFocusRingState extends State<TvFocusRing> {

  late final FocusNode _node;

  bool _focused = false;



  bool get _ownsNode => widget.focusNode == null;



  @override

  void initState() {

    super.initState();

    _node = widget.focusNode ?? FocusNode();

    _node.addListener(_onNodeChange);

  }



  @override

  void dispose() {

    _node.removeListener(_onNodeChange);

    if (_ownsNode) _node.dispose();

    super.dispose();

  }



  void _onNodeChange() {

    final f = _node.hasFocus;

    if (f != _focused) {

      setState(() => _focused = f);

      widget.onFocusChange?.call(f);

    }

  }



  KeyEventResult _onKey(FocusNode node, KeyEvent event) {

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (!TvRemoteSelectKeys.isSelect(event.logicalKey)) return KeyEventResult.ignored;

    widget.onActivate?.call();

    return KeyEventResult.handled;

  }



  @override

  Widget build(BuildContext context) {

    final cs = Theme.of(context).colorScheme;

    final active = _focused;

    final borderW = widget.borderWidth;



    return Focus(

      focusNode: _node,

      autofocus: widget.autofocus,

      onKeyEvent: _onKey,

      child: AnimatedScale(

        scale: active && widget.scaleFocused ? TvHomeLayout.focusScale : 1.0,

        duration: AppMotion.fast,

        curve: AppMotion.emphasized,

        child: Stack(

          clipBehavior: Clip.none,

          fit: StackFit.passthrough,

          children: [

            widget.child,

            if (widget.showBorder)

              Positioned(

                left: -borderW,

                top: -borderW,

                right: -borderW,

                bottom: -borderW,

                child: IgnorePointer(

                  child: AnimatedContainer(

                    duration: AppMotion.fast,

                    curve: AppMotion.emphasized,

                    decoration: BoxDecoration(

                      borderRadius: BorderRadius.circular(

                        widget.borderRadius + borderW,

                      ),

                      border: Border.all(

                        color: active ? cs.primary : Colors.transparent,

                        width: borderW,

                      ),

                    ),

                  ),

                ),

              ),

          ],

        ),

      ),

    );

  }

}

