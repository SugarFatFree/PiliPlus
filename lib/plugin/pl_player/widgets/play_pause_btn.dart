import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({
    super.key,
    required this.plPlayerController,
  });

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final StreamSubscription<bool> subscription;
  late Player player;

  @override
  void initState() {
    super.initState();
    player = widget.plPlayerController.videoPlayerController!;
    controller = AnimationController(
      vsync: this,
      value: player.state.playing ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    subscription = player.stream.playing.listen((playing) {
      if (playing) {
        controller.forward();
      } else {
        controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animIcon = Center(
      child: AnimatedIcon(
        semanticLabel: player.state.playing ? '暂停' : '播放',
        progress: controller,
        icon: AnimatedIcons.play_pause,
        color: Colors.white,
        size: 20,
      ),
    );
    return SizedBox(
      width: 42,
      height: 34,
      child: PlatformUtils.isTV
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                autofocus: true,
                onTap: widget.plPlayerController.onDoubleTapCenter,
                borderRadius: BorderRadius.circular(8),
                focusColor: Colors.white24,
                child: animIcon,
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.plPlayerController.onDoubleTapCenter,
              child: animIcon,
            ),
    );
  }
}
