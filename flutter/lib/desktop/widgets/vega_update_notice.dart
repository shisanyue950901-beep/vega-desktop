// Vega 新增文件（AGPL-3.0，基于 RustDesk 1.5.3 修改版）：
// 启动后自动检查更新，发现新版本时在首页显示提示条、在侧栏「设置」上显示小圆点。
// 只做检查，不自动下载或安装；安装仍在「设置 → 关于」里由用户点「立即更新」。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/vega_shot.dart';
import 'package:flutter_hbb/vega_theme.dart';
import 'package:get/get.dart';

/// 发现的新版本号；空字符串表示没有。
final RxString vegaUpdateAvailable = ''.obs;
final RxString vegaUpdateNotes = ''.obs;

bool _started = false;
Timer? _poll;

Map<String, dynamic> _state() {
  try {
    final v = jsonDecode(bind.mainVegaUpdateState());
    if (v is Map<String, dynamic>) return v;
  } catch (_) {}
  return const {};
}

void _apply(Map<String, dynamic> m) {
  final phase = (m['phase'] ?? '').toString();
  if (phase == 'available') {
    vegaUpdateAvailable.value = (m['version'] ?? '').toString();
    vegaUpdateNotes.value = (m['notes'] ?? '').toString();
  } else if (phase == 'latest') {
    vegaUpdateAvailable.value = '';
    vegaUpdateNotes.value = '';
  }
}

void _checkOnce() {
  final phase = (_state()['phase'] ?? 'idle').toString();
  // 正在检查/下载/安装，或已经发现新版本时不重复检查。
  if (const {'checking', 'downloading', 'installing', 'available'}
      .contains(phase)) {
    _apply(_state());
    return;
  }
  try {
    bind.mainVegaUpdateCheck();
  } catch (_) {
    return;
  }
  var n = 0;
  _poll?.cancel();
  _poll = Timer.periodic(const Duration(seconds: 2), (t) {
    n++;
    final m = _state();
    final p = (m['phase'] ?? '').toString();
    if (p != 'checking' || n > 45) {
      t.cancel();
      _apply(m);
    }
  });
}

/// 主窗口启动后调用一次：12 秒后检查，之后每 6 小时检查一次。仅 Windows。
void vegaStartAutoUpdateCheck() {
  if (_started || !isWindows) return;
  _started = true;
  // CI 截图：模拟发现新版本，不联网。
  if (vegaShotEnv('VEGA_SHOT_UPD') == '1') {
    vegaUpdateAvailable.value = '0.7.9';
    vegaUpdateNotes.value = '· 这是截图用的示例更新说明';
    return;
  }
  if (vegaShotEnv('VEGA_SHOT_NAV') != null ||
      vegaShotEnv('VEGA_SHOT_ABOUT') != null) {
    return;
  }
  Timer(const Duration(seconds: 12), _checkOnce);
  Timer.periodic(const Duration(hours: 6), (_) => _checkOnce());
}

/// 首页提示条：发现新版本时出现，点「查看」进入「设置 → 关于」。
class VegaUpdateBanner extends StatelessWidget {
  const VegaUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = vegaUpdateAvailable.value;
      if (v.isEmpty) return const SizedBox.shrink();
      final p = VegaColors.of(context);
      final firstNote = vegaUpdateNotes.value
          .split('\n')
          .map((e) => e.trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      return Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.accent.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: VegaColors.aurora,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  size: 17, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Vega $v 可以更新了',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: p.text)),
                  if (firstNote.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(firstNote.replaceFirst(RegExp(r'^[·•\-]\s*'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.secondary)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () =>
                    DesktopSettingPage.vegaShowEmbedded(SettingsTabKey.about),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: VegaColors.aurora,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('查看',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
