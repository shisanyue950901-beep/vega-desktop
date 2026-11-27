import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/install_directory_confirmation.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/vega_theme.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

// Vega 修改：安装页改为 Vega 品牌单卡片布局（2026-11-24）。
const _vegaSourceUrl = 'https://github.com/shisanyue950901-beep/vega-desktop';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _InstallPageState() {
    Get.put<DesktopTabController>(tabController);
    const label = "install";
    tabController.add(TabInfo(
        key: label,
        label: label,
        closable: false,
        page: _InstallPageBody(
          key: const ValueKey(label),
        )));
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<DesktopTabController>();
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
      enableResizeEdges: windowManagerEnableResizeEdges,
      child: Container(
        child: Scaffold(
            backgroundColor: VegaColors.of(context).bg,
            body: DesktopTab(controller: tabController)),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  static const _printerStatusTimeout = Duration(seconds: 5);

  late final TextEditingController controller;
  final RxBool startmenu = true.obs;
  final RxBool desktopicon = true.obs;
  final RxBool printer = false.obs;
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;
  final RxBool cancelEnabled = true.obs;
  Timer? _failTimer;

  // todo move to theme.
  final buttonStyle = OutlinedButton.styleFrom(
    textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
    padding: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
  );

  _InstallPageBodyState() {
    controller = TextEditingController(text: bind.installInstallPath());
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu.value = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon.value = installOptions['DESKTOPSHORTCUTS'] != '0';
    printer.value = installOptions['PRINTER'] == '1';
  }

  Future<void> _loadPrinterStatus() async {
    btnEnabled.value = false;
    showProgress.value = true;
    try {
      final status = await bind
          .mainGetCommon(key: 'is-printer-installed')
          .timeout(_printerStatusTimeout);
      printer.value = status == 'true';
      if (status != 'true' && status != 'false') {
        debugPrint('Failed to check printer installation status: $status');
      }
    } catch (e) {
      printer.value = false;
      debugPrint('Failed to check printer installation status: $e');
    } finally {
      showProgress.value = false;
      btnEnabled.value = true;
    }
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
    if (printer.value) {
      _loadPrinterStatus();
    }
  }

  @override
  void dispose() {
    _failTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  Widget _switchRow(VegaPalette p, RxBool option, String label) {
    return Obx(() => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: btnEnabled.value ? () => option.value = !option.value : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 14, color: p.text)),
                ),
                Switch(
                  value: option.value,
                  activeColor: Colors.white,
                  activeTrackColor: p.accent,
                  onChanged: btnEnabled.value
                      ? (v) => option.value = v
                      : null,
                ),
              ],
            ),
          ),
        ));
  }

  Widget _installButton(VegaPalette p) {
    return Obx(() {
      final enabled = btnEnabled.value;
      final busy = showProgress.value;
      return Opacity(
        opacity: enabled || busy ? 1 : 0.6,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            gradient: VegaColors.aurora,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: VegaColors.auroraStart.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? install : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Center(
                  child: Text(busy ? '正在安装…' : '立即安装',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = VegaColors.of(context);
    return Scaffold(
        backgroundColor: p.bg,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VegaEntrance(
                child: Row(
                  children: [
                    const VegaMark(size: 48),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('安装 Vega',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: p.text)),
                        const SizedBox(height: 4),
                        Text('开源、免费的远程协助，装好就能用',
                            style:
                                TextStyle(fontSize: 13, color: p.secondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              VegaEntrance(
                delayMs: 80,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(p.radius),
                    border: Border.all(color: p.separator),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('安装位置',
                          style: TextStyle(fontSize: 12, color: p.secondary)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: controller,
                              builder: (context, value, child) => Text(
                                value.text,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: p.text),
                              ),
                            ),
                          ),
                          Obx(() => TextButton(
                                onPressed:
                                    btnEnabled.value ? selectInstallPath : null,
                                style: TextButton.styleFrom(
                                    foregroundColor: p.accent),
                                child: const Text('更改'),
                              )),
                        ],
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, child) =>
                            InstallDirectoryWarning(directoryPath: value.text),
                      ),
                      Divider(height: 18, color: p.separator),
                      _switchRow(p, startmenu, '添加到开始菜单'),
                      _switchRow(p, desktopicon, '在桌面创建快捷方式'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              VegaEntrance(
                delayMs: 160,
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                        'Vega 基于开源项目 RustDesk 修改，按 AGPL-3.0 发布。安装时 Windows 会请求一次管理员确认。',
                        style: TextStyle(fontSize: 12, color: p.secondary)),
                    InkWell(
                      onTap: () => launchUrlString(_vegaSourceUrl),
                      child: Text('查看源代码',
                          style: TextStyle(fontSize: 12, color: p.accent)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    // NOT use Offstage to wrap LinearProgressIndicator
                    child: Obx(() => showProgress.value
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              color: p.accent,
                              backgroundColor: p.separator,
                            ),
                          ).marginOnly(right: 16)
                        : const SizedBox.shrink()),
                  ),
                  Obx(() => TextButton(
                        onPressed: cancelEnabled.value
                            ? () => windowManager.close()
                            : null,
                        style: TextButton.styleFrom(
                            foregroundColor: p.secondary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 14)),
                        child: const Text('取消'),
                      )).marginOnly(right: 8),
                  _installButton(p),
                ],
              ),
            ],
          ).paddingSymmetric(horizontal: 44, vertical: 36),
        ));
  }

  Future<void> install() async {
    if (!btnEnabled.value) return;
    final installPath = controller.text;
    do_install() {
      btnEnabled.value = false;
      cancelEnabled.value = false;
      showProgress.value = true;
      String args = '';
      if (startmenu.value) args += ' startmenu';
      if (desktopicon.value) args += ' desktopicon';
      if (printer.value) args += ' printer';
      bind.installInstallMe(options: args, path: installPath);
      // Vega 修改：安装成功进程会退出；UAC 取消或失败时进程保留，
      // 轮询失败标记，恢复按钮让用户可以再点安装。
      _failTimer?.cancel();
      _failTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (bind.installTakeFailed()) {
          t.cancel();
          showProgress.value = false;
          cancelEnabled.value = true;
          btnEnabled.value = true;
        }
      });
    }

    btnEnabled.value = false;
    try {
      final confirmed =
          await confirmInstallDirectory(this.context, targetPath: installPath);
      if (!mounted || !confirmed) return;
      do_install();
    } finally {
      if (mounted && !showProgress.value) btnEnabled.value = true;
    }
  }

  void selectInstallPath() async {
    String? install_path = await FilePicker.platform
        .getDirectoryPath(initialDirectory: controller.text);
    if (install_path != null) {
      controller.text = join(install_path, await bind.mainGetAppName());
    }
  }
}
