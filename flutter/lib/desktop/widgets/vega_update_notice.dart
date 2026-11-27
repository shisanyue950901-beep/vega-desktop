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
  vegaSyncUpdateNotice((m['phase'] ?? '').toString(),
      (m['version'] ?? '').toString(), (m['notes'] ?? '').toString());
}

void _pollUntilSettled() {
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

void _checkOnce() {
  final m = _state();
  final phase = (m['phase'] ?? 'idle').toString();
  // 只在空闲或已是最新时自动检查；正在检查/下载/安装、已发现新版本、
  // 或安装失败等待用户重试（error 保留清单）时都不打断。
  if (phase == 'checking') {
    _pollUntilSettled();
    return;
  }
  final version = (m['version'] ?? '').toString();
  // error 且版本为空 = 上次检查失败（如断网），可以重新检查；
  // error 且有版本 = 安装失败、清单保留等待用户重试，不打断。
  final retryableCheck = phase == 'error' && version.isEmpty;
  if (phase != 'idle' && phase != 'latest' && !retryableCheck) {
    _apply(m);
    return;
  }
  try {
    bind.mainVegaUpdateCheck();
  } catch (_) {
    return;
  }
  _pollUntilSettled();
}

/// 把更新状态同步给首页提示条和侧栏红点。
void vegaSyncUpdateNotice(String phase, String version, String notes) {
  if (phase == 'available') {
    vegaUpdateAvailable.value = version;
    vegaUpdateNotes.value = notes;
  } else if (phase == 'latest' || (phase == 'error' && version.isEmpty)) {
    // 已是最新，或检查失败（版本信息已失效）：撤下提示。
    vegaUpdateAvailable.value = '';
    vegaUpdateNotes.value = '';
  }
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
  // 主窗口独立跟踪状态（含「关于」页或锁定卡发起的手动检查），不依赖更新卡是否还在。
  Timer.periodic(const Duration(seconds: 5), (_) => _apply(_state()));
  Timer.periodic(const Duration(hours: 6), (_) => _checkOnce());
}

/// 首页提示条：发现新版本时出现，点「查看」进入「设置 → 关于」。
class VegaUpdateBanner extends StatelessWidget {
  const VegaUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = vegaUpdateAvailable.value;
      // 设置被禁用时不提供入口（与侧栏一致）。
      if (v.isEmpty || bind.isDisableSettings()) return const SizedBox.shrink();
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
