// Vega：远程窗口的「控制中心」工具栏（iOS 控制中心风格，毛玻璃 + 弹性展开）。
// Modified for Vega (AGPL-3.0). 新文件，不含上游代码。
//
// 组件只负责界面和动画；状态与回调由远程窗口传入。

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../vega_theme.dart';

/// 控制中心需要的全部状态。
class VegaCcState {
  final String peerName;
  final bool direct; // 直连 / 中继
  final int latencyMs;
  final int fps;
  final String quality; // 例如「原生 4K」
  final String display; // 例如「显示器 1 / 2」
  final bool audio;
  final bool clipboard;
  final bool viewOnly;
  final bool privacy;
  final bool recording;

  const VegaCcState({
    required this.peerName,
    required this.direct,
    required this.latencyMs,
    required this.fps,
    required this.quality,
    required this.display,
    required this.audio,
    required this.clipboard,
    required this.viewOnly,
    required this.privacy,
    required this.recording,
  });
}

/// 控制中心回调。名字即动作，键为开关名（audio/clipboard/view_only/privacy/recording）。
class VegaCcActions {
  final VoidCallback? onQuality;
  final VoidCallback? onDisplay;
  final VoidCallback? onFiles;
  final void Function(String key, bool value)? onToggle;
  final VoidCallback? onCtrlAltDel;
  final VoidCallback? onLock;
  final VoidCallback? onRestart;
  final VoidCallback? onScreenshot;
  final VoidCallback? onDisconnect;
  // 让对端（代理）给它局域网里的其他设备发开机信号。
  final VoidCallback? onWake;
  // 打开原版完整工具栏（键盘模式、多显示器等暂未搬进控制中心的功能）。
  final VoidCallback? onMore;

  const VegaCcActions({
    this.onQuality,
    this.onDisplay,
    this.onFiles,
    this.onToggle,
    this.onCtrlAltDel,
    this.onLock,
    this.onRestart,
    this.onScreenshot,
    this.onDisconnect,
    this.onWake,
    this.onMore,
  });
}

/// 收起时是顶部小条，点击展开成毛玻璃面板。
/// 未固定时：鼠标离开 2.5 秒后缩成顶部一条细线，鼠标移到细线处再出现。
/// 面板里的图钉可固定常显。
class VegaControlCenter extends StatefulWidget {
  final VegaCcState state;
  final VegaCcActions actions;
  final bool initiallyExpanded;
  final bool pinned;
  final ValueChanged<bool>? onPinChanged;

  const VegaControlCenter({
    Key? key,
    required this.state,
    this.actions = const VegaCcActions(),
    this.initiallyExpanded = false,
    this.pinned = false,
    this.onPinChanged,
  }) : super(key: key);

  @override
  State<VegaControlCenter> createState() => _VegaControlCenterState();
}

class _VegaControlCenterState extends State<VegaControlCenter> {
  static const _hideDelay = Duration(milliseconds: 2500);
  late bool _expanded = widget.initiallyExpanded;
  late bool _pinned = widget.pinned;
  bool _hovering = false;
  bool _hidden = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide(); // 刚连上时先露出 2.5 秒，让用户知道它在这里。
  }

  @override
  void didUpdateWidget(VegaControlCenter old) {
    super.didUpdateWidget(old);
    if (old.pinned != widget.pinned) {
      _pinned = widget.pinned;
      if (_pinned && _hidden) setState(() => _hidden = false);
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // 展开的面板也一样：鼠标离开 2.5 秒后收起并缩成细线。
    if (_pinned || _hovering) return;
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && !_pinned && !_hovering) {
        setState(() {
          _expanded = false;
          _hidden = true;
        });
      }
    });
  }

  void _onEnter() {
    _hovering = true;
    _hideTimer?.cancel();
    if (_hidden) setState(() => _hidden = false);
  }

  void _onExit() {
    _hovering = false;
    _scheduleHide();
  }

  void _togglePin() {
    setState(() {
      _pinned = !_pinned;
      if (_pinned) _hidden = false;
    });
    widget.onPinChanged?.call(_pinned);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          // 不用 SizeTransition：它的 Align 会把整块推到左边。
          child: SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0, -0.25), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: _hidden
            ? _Handle(key: const ValueKey('handle'), dark: dark)
            : KeyedSubtree(
                key: const ValueKey('cc'), child: _content(dark)),
      ),
    );
  }

  Widget _content(bool dark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pill(
          state: widget.state,
          expanded: _expanded,
          dark: dark,
          onTap: () {
            setState(() => _expanded = !_expanded);
            _scheduleHide();
          },
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          reverseDuration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              alignment: Alignment.topCenter,
              scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
              child: child,
            ),
          ),
          child: _expanded
              ? _Panel(
                  key: const ValueKey('panel'),
                  state: widget.state,
                  actions: widget.actions,
                  dark: dark,
                  pinned: _pinned,
                  onPin: _togglePin,
                )
              : const SizedBox.shrink(key: ValueKey('none')),
        ),
      ],
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool dark;
  final EdgeInsets padding;

  const _Glass({
    required this.child,
    required this.radius,
    required this.dark,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.45 : 0.18),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: dark
                  ? const Color(0xFF1C1B26).withOpacity(0.55)
                  : Colors.white.withOpacity(0.55),
              border: Border.all(
                color: Colors.white.withOpacity(dark ? 0.12 : 0.6),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

Color _fg(bool dark) => dark ? Colors.white : const Color(0xFF1C1C1E);
Color _sub(bool dark) =>
    dark ? Colors.white.withOpacity(0.62) : const Color(0xFF1C1C1E).withOpacity(0.55);

class _Pill extends StatelessWidget {
  final VegaCcState state;
  final bool expanded;
  final bool dark;
  final VoidCallback onTap;

  const _Pill({
    required this.state,
    required this.expanded,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dot = state.direct ? const Color(0xFF30D158) : const Color(0xFFFF9F0A);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: _Glass(
          radius: 18,
          dark: dark,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                '${state.peerName}  ·  ${state.direct ? '直连' : '中继'}  ·  ${state.latencyMs} ms',
                style: TextStyle(
                    fontSize: 12, color: _fg(dark), fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: _sub(dark)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 隐藏时留在顶部的细线，鼠标移上去整个控制中心就回来。
class _Handle extends StatelessWidget {
  final bool dark;

  const _Handle({Key? key, required this.dark}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 外层透明区域放大鼠标感应范围，细线本身只占很小一块。
    return Container(
      width: 200,
      height: 18,
      color: Colors.transparent,
      alignment: Alignment.topCenter,
      child: Container(
        width: 56,
        height: 5,
        decoration: BoxDecoration(
          color: (dark ? Colors.white : Colors.black).withOpacity(0.35),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color: (dark ? Colors.black : Colors.white).withOpacity(0.5),
              width: 0.5),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final VegaCcState state;
  final VegaCcActions actions;
  final bool dark;
  final bool pinned;
  final VoidCallback? onPin;

  const _Panel({
    Key? key,
    required this.state,
    required this.actions,
    required this.dark,
    this.pinned = false,
    this.onPin,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 380,
      child: _Glass(
        radius: 26,
        dark: dark,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusRow(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _BigTile(
                        dark: dark,
                        icon: Icons.high_quality_outlined,
                        title: '画质',
                        value: state.quality,
                        onTap: actions.onQuality)),
                const SizedBox(width: 10),
                Expanded(
                    child: _BigTile(
                        dark: dark,
                        icon: Icons.monitor_outlined,
                        title: '显示器',
                        value: state.display,
                        onTap: actions.onDisplay)),
                const SizedBox(width: 10),
                Expanded(
                    child: _BigTile(
                        dark: dark,
                        icon: Icons.folder_copy_outlined,
                        title: '文件传输',
                        value: '打开',
                        onTap: actions.onFiles)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _toggle('audio', Icons.volume_up_rounded, '声音', state.audio),
                _toggle('clipboard', Icons.content_paste_rounded, '剪贴板',
                    state.clipboard),
                _toggle('view_only', Icons.visibility_rounded, '仅观看',
                    state.viewOnly),
                _toggle('privacy', Icons.visibility_off_rounded, '隐私黑屏',
                    state.privacy),
                _toggle('recording', Icons.fiber_manual_record_rounded, '录屏',
                    state.recording,
                    activeColor: const Color(0xFFFF453A)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _ActionChip(
                        dark: dark,
                        icon: Icons.keyboard_command_key_rounded,
                        label: 'Ctrl+Alt+Del',
                        onTap: actions.onCtrlAltDel)),
                const SizedBox(width: 8),
                Expanded(
                    child: _ActionChip(
                        dark: dark,
                        icon: Icons.lock_outline_rounded,
                        label: '锁屏',
                        onTap: actions.onLock)),
                const SizedBox(width: 8),
                Expanded(
                    child: _ActionChip(
                        dark: dark,
                        icon: Icons.restart_alt_rounded,
                        label: '重启',
                        onTap: actions.onRestart)),
                const SizedBox(width: 8),
                Expanded(
                    child: _ActionChip(
                        dark: dark,
                        icon: Icons.photo_camera_outlined,
                        label: '截图',
                        onTap: actions.onScreenshot)),
                if (actions.onMore != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _ActionChip(
                          dark: dark,
                          icon: Icons.more_horiz_rounded,
                          label: '更多',
                          onTap: actions.onMore)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (actions.onWake != null) ...[
                  Expanded(
                    child: _Pressable(
                      onTap: actions.onWake,
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: dark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.power_settings_new_rounded,
                                size: 16, color: _fg(dark)),
                            const SizedBox(width: 6),
                            Text('远程开机',
                                style: TextStyle(
                                    color: _fg(dark),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _Pressable(
                    onTap: actions.onDisconnect,
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF453A),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_off_rounded, size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text('断开连接',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow() {
    Widget chip(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        );
    final linkColor =
        state.direct ? const Color(0xFF30D158) : const Color(0xFFFF9F0A);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: VegaColors.aurora,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            state.peerName.isNotEmpty ? state.peerName[0].toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(state.peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _fg(dark))),
        ),
        chip(state.direct ? '直连' : '中继', linkColor),
        const SizedBox(width: 6),
        chip('${state.latencyMs} ms', _sub(dark)),
        const SizedBox(width: 6),
        chip('${state.fps} 帧', _sub(dark)),
        const SizedBox(width: 4),
        Tooltip(
          message: pinned ? '取消固定（不用时自动隐藏）' : '固定显示',
          child: _Pressable(
            onTap: onPin,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 17,
                  color: pinned ? VegaColors.auroraStart : _sub(dark)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggle(String key, IconData icon, String label, bool on,
      {Color? activeColor}) {
    return _RoundToggle(
      dark: dark,
      icon: icon,
      label: label,
      on: on,
      activeColor: activeColor ?? VegaColors.auroraStart,
      onTap: actions.onToggle == null
          ? null
          : () => actions.onToggle!(key, !on),
    );
  }
}

/// 按下时轻微缩小，松开回弹，模拟 iOS 的按压手感。
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  final bool dark;
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _BigTile({
    required this.dark,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 78,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                gradient: VegaColors.aurora,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _fg(dark))),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: _sub(dark))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundToggle extends StatelessWidget {
  final bool dark;
  final IconData icon;
  final String label;
  final bool on;
  final Color activeColor;
  final VoidCallback? onTap;

  const _RoundToggle({
    required this.dark,
    required this.icon,
    required this.label,
    required this.on,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final offBg =
        dark ? Colors.white.withOpacity(0.10) : Colors.white.withOpacity(0.65);
    return SizedBox(
      width: 62,
      child: Column(
        children: [
          _Pressable(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: on ? activeColor : offBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 21, color: on ? Colors.white : _fg(dark)),
            ),
          ),
          const SizedBox(height: 5),
          Text(label,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: _fg(dark))),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final bool dark;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.dark,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: _fg(dark)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: _fg(dark))),
          ],
        ),
      ),
    );
  }
}

/// CI 截图用：模拟一张远程桌面，控制中心叠在上面，看毛玻璃效果。
class VegaControlCenterPreview extends StatelessWidget {
  final bool expanded;

  const VegaControlCenterPreview({Key? key, this.expanded = true})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 浅色截图演示直连原生 4K；深色截图演示走中继时的提示。
    final relay = Theme.of(context).brightness == Brightness.dark;
    final state = VegaCcState(
      peerName: 'Caps-PC',
      direct: !relay,
      latencyMs: relay ? 48 : 12,
      fps: 60,
      quality: relay ? '4K · 中继受限' : '原生 4K',
      display: '显示器 1 / 2',
      audio: true,
      clipboard: true,
      viewOnly: false,
      privacy: false,
      recording: false,
    );
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _MockDesktop())),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: VegaControlCenter(
                state: state,
                initiallyExpanded: expanded,
                // 展开预览固定住，避免截图前自动收起；收起预览用来拍细线。
                pinned: expanded,
                actions: VegaCcActions(onWake: () {}, onMore: () {}),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockDesktop extends CustomPainter {
  const _MockDesktop();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F4C81), Color(0xFF3A1C71), Color(0xFFD76D77)],
          ).createShader(rect));
    // 几个「窗口」，让毛玻璃后面有内容可以被模糊。
    void win(double l, double t, double w, double h, Color bar, Color body) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * l, size.height * t, size.width * w,
              size.height * h),
          const Radius.circular(8));
      canvas.drawRRect(r, Paint()..color = body);
      canvas.drawRRect(
          RRect.fromRectAndCorners(
              Rect.fromLTWH(r.left, r.top, r.width, 28),
              topLeft: const Radius.circular(8),
              topRight: const Radius.circular(8)),
          Paint()..color = bar);
      final line = Paint()..color = bar.withOpacity(0.5);
      for (var i = 0; i < 6; i++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(r.left + 16, r.top + 48 + i * 22,
                    r.width * (0.4 + 0.08 * (i % 4)), 10),
                const Radius.circular(5)),
            line);
      }
    }

    win(0.18, 0.06, 0.42, 0.55, const Color(0xFF2D7FF9), Colors.white);
    win(0.48, 0.30, 0.40, 0.50, const Color(0xFFFFB020), const Color(0xFFF7F7F7));
    win(0.05, 0.55, 0.30, 0.35, const Color(0xFF20C997), const Color(0xFF1E1E1E));
    // 任务栏
    canvas.drawRect(
        Rect.fromLTWH(0, size.height - 40, size.width, 40),
        Paint()..color = const Color(0xFF202020).withOpacity(0.85));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
