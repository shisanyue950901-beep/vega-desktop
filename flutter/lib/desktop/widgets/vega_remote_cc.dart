// Vega 新增文件（AGPL-3.0，基于 RustDesk 1.5.3 修改版）：
// 把控制中心（vega_control_center.dart）接到真实远程会话。
// 能复用上游的就复用上游菜单项（Ctrl+Alt+Del、锁屏、重启、截图、隐私黑屏），
// 保证权限判断和对端版本兼容与原工具栏一致。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/desktop/widgets/vega_control_center.dart';
import 'package:get/get.dart';

class VegaRemoteCc extends StatefulWidget {
  final String id;
  final FFI ffi;
  final VoidCallback onMore;

  const VegaRemoteCc(
      {Key? key, required this.id, required this.ffi, required this.onMore})
      : super(key: key);

  @override
  State<VegaRemoteCc> createState() => _VegaRemoteCcState();
}

class _VegaRemoteCcState extends State<VegaRemoteCc> {
  Timer? _tick;
  String _quality = '';

  FFI get ffi => widget.ffi;
  SessionID get sid => ffi.sessionId;

  static const _qualities = [
    kRemoteImageQualityBest,
    kRemoteImageQualityBalanced,
    kRemoteImageQualityLow,
  ];
  static const _qualityLabel = {
    kRemoteImageQualityBest: '最佳画质',
    kRemoteImageQualityBalanced: '均衡',
    kRemoteImageQualityLow: '流畅优先',
  };

  @override
  void initState() {
    super.initState();
    PrivacyModeState.init(widget.id);
    _loadQuality();
    // 延迟、帧率、开关状态来自会话，1 秒刷新一次足够。
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadQuality() async {
    final q = await bind.sessionGetImageQuality(sessionId: sid) ?? '';
    if (mounted) setState(() => _quality = q);
  }

  bool _opt(String key) =>
      bind.sessionGetToggleOptionSync(sessionId: sid, arg: key);

  int _num(String? s) =>
      int.tryParse(RegExp(r'\d+').firstMatch(s ?? '')?.group(0) ?? '') ?? 0;

  // 在上游菜单里按 actionId 找到对应项并执行，没有（无权限/对端不支持）就为 null。
  VoidCallback? _upstream(String actionId) {
    try {
      final items = toolbarControls(context, widget.id, ffi);
      for (final m in items) {
        if (m.actionId == actionId) return m.onPressed;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _toggle(String key, bool value) async {
    switch (key) {
      case 'audio':
        await bind.sessionToggleOption(sessionId: sid, value: 'disable-audio');
        break;
      case 'clipboard':
        await bind.sessionToggleOption(
            sessionId: sid, value: 'disable-clipboard');
        break;
      case 'view_only':
        await bind.sessionToggleOption(
            sessionId: sid, value: kOptionToggleViewOnly);
        ffi.ffiModel.setViewOnly(widget.id, value);
        break;
      case 'privacy':
        final items = toolbarPrivacyMode(
            PrivacyModeState.find(widget.id), context, widget.id, ffi);
        if (items.isNotEmpty) items.first.onChanged?.call(value);
        break;
      case 'recording':
        await ffi.recordingModel.toggle();
        break;
    }
    if (mounted) setState(() {});
  }

  Future<void> _nextQuality() async {
    final i = _qualities.indexOf(_quality);
    final next = _qualities[(i + 1) % _qualities.length];
    await bind.sessionSetImageQuality(sessionId: sid, value: next);
    if (mounted) setState(() => _quality = next);
  }

  void _nextDisplay() {
    final pi = ffi.ffiModel.pi;
    final n = pi.displays.length;
    if (n <= 1) return;
    final cur = pi.currentDisplay == kAllDisplayValue ? 0 : pi.currentDisplay;
    openMonitorInTheSameTab((cur + 1) % n, ffi, pi);
    setState(() {});
  }

  // 远程开机：让当前连着的这台电脑（代理）给同一局域网里的目标设备发开机信号。
  // 代理按自己记录的局域网设备 MAC 发送，结果由对端回传后弹窗显示。
  Future<void> _wake() async {
    List<Map<String, dynamic>> peers = [];
    try {
      final raw = await bind.mainLoadRecentPeersForAb(filter: '');
      if (raw.isNotEmpty) {
        peers = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => (e['id'] ?? '') != widget.id)
            .toList();
      }
    } catch (_) {}
    final ctrl = TextEditingController();
    final valid = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
    ffi.dialogManager.show((setState, close, context) {
      void send(String id) {
        id = id.replaceAll(' ', '').trim();
        if (!valid.hasMatch(id)) return;
        bind.sessionVegaWake(sessionId: sid, targetId: id);
        close();
        showToast('已让这台电脑发送开机信号');
      }

      String label(Map<String, dynamic> p) {
        final a = (p['alias'] ?? '').toString();
        final h = (p['hostname'] ?? '').toString();
        return a.isNotEmpty ? a : (h.isNotEmpty ? h : p['id'].toString());
      }

      return CustomAlertDialog(
        title: const Text('远程开机'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '由当前连接的电脑代发开机信号。目标电脑需要和它在同一局域网、插网线，并在 BIOS 里打开网络唤醒。',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                    labelText: '目标设备 ID', isDense: true),
                onSubmitted: send,
              ),
              if (peers.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    shrinkWrap: true,
                    children: peers
                        .map((p) => ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              leading: const Icon(
                                  Icons.desktop_windows_outlined,
                                  size: 18),
                              title: Text(label(p),
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(p['id'].toString()),
                              onTap: () => send(p['id'].toString()),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          dialogButton('取消', onPressed: close, isOutline: true),
          dialogButton('发送', onPressed: () => send(ctrl.text)),
        ],
        onSubmit: () => send(ctrl.text),
        onCancel: close,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = ffi.ffiModel;
    final pi = model.pi;
    final q = ffi.qualityMonitorModel.data;
    final n = pi.displays.length;
    final cur = pi.currentDisplay == kAllDisplayValue
        ? '全部'
        : '${pi.currentDisplay + 1}';
    final state = VegaCcState(
      peerName: pi.hostname.isNotEmpty ? pi.hostname : widget.id,
      direct: model.direct == true,
      latencyMs: _num(q.delay),
      fps: _num(q.fps),
      quality: _qualityLabel[_quality] ?? '自定义',
      display: n > 1 ? '显示器 $cur / $n' : '显示器 1',
      audio: !_opt('disable-audio'),
      clipboard: !_opt('disable-clipboard'),
      viewOnly: model.viewOnly,
      privacy: PrivacyModeState.find(widget.id).value.isNotEmpty,
      recording: ffi.recordingModel.start,
    );
    return VegaControlCenter(
      state: state,
      actions: VegaCcActions(
        onQuality: _nextQuality,
        onDisplay: n > 1 ? _nextDisplay : null,
        onFiles: () => connect(context, widget.id, isFileTransfer: true),
        onToggle: (k, v) => _toggle(k, v),
        onCtrlAltDel: _upstream(kShortcutActionSendCtrlAltDel),
        onLock: _upstream(kShortcutActionInsertLock),
        onRestart: _upstream(kShortcutActionRestartRemote),
        onScreenshot: _upstream(kShortcutActionScreenshot),
        onDisconnect: () => closeConnection(id: widget.id),
        onWake: _wake,
        onMore: widget.onMore,
      ),
    );
  }
}
