// Vega 新增文件（AGPL-3.0，基于 RustDesk 1.5.3 修改版）：
// 设置 → 关于 页的「检查更新」行。后端状态机在 src/vega_update.rs，
// 经 main_vega_update_* 四个 FFI 入口驱动；本组件只轮询状态并渲染。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/vega_theme.dart';

class VegaUpdateTile extends StatefulWidget {
  const VegaUpdateTile({super.key});

  @override
  State<VegaUpdateTile> createState() => _VegaUpdateTileState();
}

class _VegaUpdateTileState extends State<VegaUpdateTile> {
  String _phase = 'idle';
  String _version = '';
  String _notes = '';
  String _error = '';
  // 上次更新的结果（重启后读一次）：'' / 'ok' / 'failed'
  String _pending = '';
  String _pendingVersion = '';
  Timer? _timer;

  static const _busy = {'checking', 'downloading', 'installing'};

  @override
  void initState() {
    super.initState();
    _readPending();
    _readState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _decode(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return const {};
  }

  void _readPending() {
    try {
      final m = _decode(bind.mainVegaUpdatePending());
      final r = (m['result'] ?? 'none').toString();
      if (r == 'ok' || r == 'failed') {
        _pending = r;
        _pendingVersion = (m['version'] ?? '').toString();
      }
    } catch (_) {}
  }

  void _readState() {
    Map<String, dynamic> m;
    try {
      m = _decode(bind.mainVegaUpdateState());
    } catch (_) {
      m = const {};
    }
    if (!mounted) return;
    setState(() {
      _phase = (m['phase'] ?? 'idle').toString();
      _version = (m['version'] ?? '').toString();
      _notes = (m['notes'] ?? '').toString();
      _error = (m['error'] ?? '').toString();
    });
    if (_busy.contains(_phase)) {
      _timer ??= Timer.periodic(
          const Duration(milliseconds: 700), (_) => _readState());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _check() {
    _pending = '';
    bind.mainVegaUpdateCheck();
    _readState();
  }

  void _install() {
    bind.mainVegaUpdateInstall();
    _readState();
  }

  @override
  Widget build(BuildContext context) {
    final p = VegaColors.of(context);
    final busy = _busy.contains(_phase);

    String title;
    String? subtitle;
    Color dot = p.secondary;
    switch (_phase) {
      case 'checking':
        title = '正在检查更新…';
        break;
      case 'latest':
        title = '已是最新版本';
        dot = const Color(0xFF34C759);
        break;
      case 'available':
        title = '发现新版本 $_version';
        subtitle = _notes.isEmpty ? null : _notes;
        dot = p.accent;
        break;
      case 'downloading':
        title = '正在下载 $_version…';
        dot = p.accent;
        break;
      case 'installing':
        title = '正在安装，完成后会自动重启';
        subtitle = '如弹出系统授权窗口，请点「是」';
        dot = p.accent;
        break;
      case 'error':
        title = _version.isNotEmpty ? '更新 $_version 没有成功' : '检查更新失败';
        subtitle = _error.isEmpty ? null : _error;
        dot = const Color(0xFFFF453A);
        break;
      default:
        if (_pending == 'ok') {
          title = '已更新到 $_pendingVersion';
          dot = const Color(0xFF34C759);
        } else if (_pending == 'failed') {
          title = '上次更新到 $_pendingVersion 没有生效';
          subtitle = '可以再检查一次';
          dot = const Color(0xFFFF453A);
        } else {
          title = '软件更新';
        }
    }

    Widget action;
    if (busy) {
      action = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
      );
    } else if (_phase == 'available' ||
        (_phase == 'error' && _version.isNotEmpty)) {
      action = _AuroraButton(
          label: _phase == 'available' ? '立即更新' : '重试', onTap: _install);
    } else {
      action = _PlainButton(label: '检查更新', onTap: _check);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.separator),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.text)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  // 更新说明未签名，只按纯文本显示，最多 3 行。
                  Text(subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.secondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}

class _AuroraButton extends StatelessWidget {
  const _AuroraButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: VegaColors.aurora,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
      ),
    );
  }
}

class _PlainButton extends StatelessWidget {
  const _PlainButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = VegaColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.accent.withOpacity(0.6)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: p.accent)),
        ),
      ),
    );
  }
}
