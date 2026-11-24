import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:flutter_hbb/vega_theme.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';
import 'package:flutter_hbb/vega_links.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  // 「本设备」卡片：临时密码默认掩码显示
  bool _obscurePassword = true;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    // Vega 修改：主界面改为单屏——品牌栏、横幅、本设备 + 远程控制两张卡、设备列表。
    // 仅「被控端」定制包仍沿用左侧窄栏。
    if (!isIncomingOnly) {
      return _buildBlock(child: buildVegaShell(context));
    }
    if (!isIncomingOnly) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      return _buildBlock(
        child: ConnectionPage(
          header: buildVegaHeader(context),
          banner: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isOutgoingOnly) buildPresetPasswordWarning(),
              Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),
            ],
          ),
          deviceCard: isOutgoingOnly
              ? null
              : ChangeNotifierProvider.value(
                  value: gFFI.serverModel,
                  child: VegaEntrance(
                    child: VegaHoverLift(child: buildDeviceCard(context)),
                  ),
                ),
        ),
      );
    }
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        if (!isIncomingOnly) const VerticalDivider(width: 1),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  /// Vega 修改：主界面 = 左侧栏 + 内容区（结构参考 UU 远程）：
  /// 远程协助（本设备 + 远程控制）/ 我的设备 / 设置。
  Widget buildVegaShell(BuildContext context) {
    vegaSettingsEmbedded = true;
    final palette = VegaColors.of(context);
    final isOutgoingOnly = bind.isOutgoingOnly();
    final pages = <Widget>[
      ConnectionPage(
        vegaStacked: true,
        header: _vegaPageTitle(palette, isOutgoingOnly ? '远程控制' : '远程协助',
            isOutgoingOnly ? '输入对方的设备 ID 即可连接' : '把 ID 和密码发给对方，或者输入对方的 ID 去连接'),
        banner: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isOutgoingOnly) buildPresetPasswordWarning(),
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),
          ],
        ),
        deviceCard: isOutgoingOnly
            ? null
            : ChangeNotifierProvider.value(
                value: gFFI.serverModel,
                child: buildAssistCard(context),
              ),
      ),
      Container(
        color: palette.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _vegaPageTitle(palette, '我的设备', '最近连接、收藏和局域网里的设备，双击即可连接'),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                padding: const EdgeInsets.fromLTRB(10, 4, 6, 0),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(palette.radius),
                  border: Border.all(color: palette.separator, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: PeerTabPage(),
              ),
            ),
          ],
        ),
      ),
      DesktopSettingPage(
          initialTabkey: SettingsTabKey.general, vegaEmbedded: true),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildVegaSidebar(context, palette),
        VerticalDivider(width: 1, thickness: 1, color: palette.separator),
        Expanded(
          child: Obx(() {
            final current = vegaNavIndex.value;
            return Stack(
              children: [
                for (var i = 0; i < pages.length; i++)
                  Offstage(
                    offstage: i != current,
                    child: TickerMode(
                      enabled: i == current,
                      child: AnimatedOpacity(
                        opacity: i == current ? 1 : 0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: pages[i],
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _vegaPageTitle(VegaPalette palette, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: palette.text)),
          const SizedBox(height: 4),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.secondary)),
        ],
      ),
    );
  }

  Widget buildVegaSidebar(BuildContext context, VegaPalette palette) {
    final dark = palette.brightness == Brightness.dark;
    Widget item(int index, IconData icon, IconData selectedIcon, String label) {
      return Obx(() {
        final selected = vegaNavIndex.value == index;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Material(
            color: selected
                ? palette.accent.withOpacity(dark ? 0.18 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => vegaNavIndex.value = index,
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 3,
                      height: selected ? 18 : 0,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(selected ? selectedIcon : icon,
                        size: 19,
                        color: selected ? palette.accent : palette.secondary),
                    const SizedBox(width: 10),
                    Text(label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? palette.accent : palette.text,
                        )),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    }

    return Container(
      width: 188,
      color: dark ? const Color(0xFF111019) : const Color(0xFFEDECF5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 12, 18),
            child: Row(
              children: [
                const VegaMark(size: 28),
                const SizedBox(width: 10),
                Text('Vega',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.text)),
              ],
            ),
          ),
          item(0, Icons.screen_share_outlined, Icons.screen_share_rounded,
              bind.isOutgoingOnly() ? '远程控制' : '远程协助'),
          item(1, Icons.devices_outlined, Icons.devices_rounded, '我的设备'),
          const Spacer(),
          if (!bind.isOutgoingOnly())
            ClipRect(child: OnlineStatusWidget().marginOnly(left: 6, bottom: 4)),
          Divider(height: 1, thickness: 1, color: palette.separator)
              .marginSymmetric(horizontal: 12),
          const SizedBox(height: 6),
          if (!bind.isDisableSettings())
            item(2, Icons.settings_outlined, Icons.settings_rounded, '设置'),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// Vega 修改：「本设备」卡片（参考 UU）：允许远程协助开关、本设备 ID、验证方式、复制并分享。
  Widget buildAssistCard(BuildContext context) {
    final palette = VegaColors.of(context);
    return Consumer<ServerModel>(builder: (context, model, child) {
      final method = model.verificationMethod;
      final showOneTime =
          model.approveMode != 'click' && method != kUsePermanentPassword;
      final pwdText = model.serverPasswd.text.trim();
      final pwdReady = showOneTime &&
          pwdText.isNotEmpty &&
          pwdText != '-' &&
          pwdText != translate('Generating ...');
      final idText = model.serverId.text;
      final labelStyle = TextStyle(fontSize: 12, color: palette.secondary);
      void copy(String text) {
        Clipboard.setData(ClipboardData(text: text));
        showToast(translate('Copied'));
      }

      const methods = [
        kUseTemporaryPassword,
        kUsePermanentPassword,
        kUseBothPasswords,
      ];
      const methodLabels = ['仅使用临时密码', '仅使用固定密码', '临时和固定密码都可用'];
      final methodLabel = model.approveMode == 'click'
          ? '对方连接时由我确认'
          : methodLabels[methods.indexOf(method)];

      Future<void> pickMethod(String value) async {
        if (value == '_set') {
          setPasswordDialog();
          return;
        }
        Future<void> apply() async {
          await model.setVerificationMethod(value);
          await model.updatePasswordModel();
        }

        if (value == kUsePermanentPassword &&
            (await bind.mainGetCommon(key: 'permanent-password-set')) !=
                'true' &&
            !isChangePermanentPasswordDisabled()) {
          setPasswordDialog(notEmptyCallback: apply);
        } else {
          await apply();
        }
      }

      final methodMenu = PopupMenuButton<String>(
        tooltip: '验证方式',
        offset: const Offset(0, 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: palette.card,
        onSelected: pickMethod,
        enabled: model.approveMode != 'click' && !bind.isDisableSettings(),
        itemBuilder: (context) => [
          for (var i = 0; i < methods.length; i++)
            PopupMenuItem<String>(
              value: methods[i],
              height: 38,
              child: Row(children: [
                SizedBox(
                  width: 18,
                  child: methods[i] == method
                      ? Icon(Icons.check_rounded,
                          size: 16, color: palette.accent)
                      : null,
                ),
                const SizedBox(width: 6),
                Text(methodLabels[i],
                    style: TextStyle(fontSize: 13, color: palette.text)),
              ]),
            ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: '_set',
            height: 38,
            enabled: !isChangePermanentPasswordDisabled(),
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text('设置固定密码…',
                  style: TextStyle(fontSize: 13, color: palette.text)),
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('验证方式：$methodLabel', style: labelStyle),
            Icon(Icons.expand_more_rounded, size: 16, color: palette.secondary),
          ]),
        ),
      );

      return Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(palette.radius),
          border: Border.all(color: palette.separator, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2B2378).withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  Text('本设备',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: palette.text)),
                  const SizedBox(width: 4),
                  buildCardIconButton(
                    context: context,
                    icon: Icons.qr_code_2_rounded,
                    tooltip: '手机扫码配置',
                    onTap: showVegaQrDialog,
                  ),
                  const Spacer(),
                  Text('允许他人远程协助',
                      style: TextStyle(fontSize: 13, color: palette.text)),
                  const SizedBox(width: 6),
                  Obx(() => Switch(
                        value: !svcStopped.value,
                        activeColor: Colors.white,
                        activeTrackColor: palette.accent,
                        onChanged: (v) => start_service(v),
                      )),
                ],
              ),
            ),
            Divider(height: 1, thickness: 0.8, color: palette.separator),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 9,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本设备 ID', style: labelStyle),
                        const SizedBox(height: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => copy(idText),
                          child: Tooltip(
                            message: translate('Copy'),
                            child: Text(
                              idText.isEmpty ? '— — —' : idText,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                height: 1.2,
                                color: palette.text,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        methodMenu,
                        const SizedBox(height: 2),
                        SizedBox(
                          height: 34,
                          child: Row(
                            children: [
                              Flexible(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: pwdReady ? () => copy(pwdText) : null,
                                  child: Text(
                                    !showOneTime
                                        ? (model.approveMode == 'click'
                                            ? '对方发起后在弹窗里确认'
                                            : '用固定密码连接')
                                        : (_obscurePassword
                                            ? '••••••'
                                            : (pwdText.isEmpty
                                                ? '—'
                                                : pwdText)),
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: showOneTime ? 20 : 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: showOneTime ? 2 : 0,
                                      fontFamily:
                                          showOneTime ? 'monospace' : null,
                                      fontFamilyFallback: showOneTime
                                          ? const ['Menlo', 'Consolas']
                                          : null,
                                      color: palette.text,
                                    ),
                                  ),
                                ),
                              ),
                              if (showOneTime)
                                buildCardIconButton(
                                  context: context,
                                  icon: _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  tooltip: _obscurePassword
                                      ? translate('Show Password')
                                      : translate('Hide Password'),
                                  onTap: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              if (showOneTime)
                                AnimatedRotationWidget(
                                  onPressed: () =>
                                      bind.mainUpdateTemporaryPassword(),
                                  child: Tooltip(
                                    message: translate('Refresh Password'),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(Icons.refresh_rounded,
                                          size: 18, color: palette.secondary),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => copy(pwdReady
                        ? '设备 ID：$idText\n临时密码：$pwdText'
                        : idText),
                    icon: const Icon(Icons.ios_share_rounded, size: 16),
                    label: const Text('复制并分享'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accent,
                      side: BorderSide(color: palette.separator),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadPowered(context),
        ),
      Align(
        alignment: Alignment.center,
        child: loadLogo(),
      ),
      buildTip(context),
      if (!isOutgoingOnly) buildDeviceCard(context),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6)
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 280.0 : 200.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: children,
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  /// Vega 修改：「本设备」深空主卡片——ID 与临时密码大字直接显示，点哪个复制哪个，
  /// 底部一个白色主按钮「复制 ID 和密码」。
  Widget buildDeviceCard(BuildContext context) {
    final palette = VegaColors.of(context);
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        final showOneTime = model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;
        // 临时密码只有在真正可用时才允许复制 / 分享：
        // 非空、不是占位 '-'，也不在生成中（生成中显示 "Generating ..."）。
        final pwdText = model.serverPasswd.text.trim();
        final pwdReady = showOneTime &&
            pwdText.isNotEmpty &&
            pwdText != '-' &&
            pwdText != translate('Generating ...');
        final idText = model.serverId.text;
        final labelStyle = TextStyle(
            fontSize: 12, color: Colors.white.withOpacity(0.62), height: 1.2);
        const mono = ['Menlo', 'Consolas', 'Courier New'];
        void copy(String text) {
          Clipboard.setData(ClipboardData(text: text));
          showToast(translate("Copied"));
        }

        return Container(
          decoration: BoxDecoration(
            gradient: VegaColors.space,
            borderRadius: BorderRadius.circular(palette.radius),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2B2378).withOpacity(0.28),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              const Positioned.fill(child: VegaStars()),
              // Vega 修改：仅接入模式下卡片在可滚动区域（高度无界），不能用 Spacer。
              LayoutBuilder(builder: (context, box) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 18),
                child: Column(
                  mainAxisSize: box.hasBoundedHeight
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF5BE49B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '允许别人控制本机',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        buildCardIconButton(
                          context: context,
                          onHero: true,
                          icon: Icons.qr_code_2_rounded,
                          tooltip: '手机扫码配置',
                          onTap: showVegaQrDialog,
                        ),
                        if (!bind.isDisableSettings())
                          buildCardIconButton(
                            context: context,
                            onHero: true,
                            icon: Icons.tune_rounded,
                            tooltip: translate('Change Password'),
                            onTap: () => DesktopSettingPage.switch2page(
                                SettingsTabKey.safety),
                          ),
                      ],
                    ),
                    if (box.hasBoundedHeight)
                      const Spacer()
                    else
                      const SizedBox(height: 14),
                    Text('设备 ID', style: labelStyle),
                    const SizedBox(height: 2),
                    // Vega 修改：InkWell 可 Tab 聚焦、Enter/Space 触发复制。
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => copy(idText),
                      child: Tooltip(
                        message: translate('Copy'),
                        child: Text(
                          idText.isEmpty ? '— — —' : idText,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            height: 1.15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(showOneTime ? '临时密码' : '密码',
                                  style: labelStyle),
                              const SizedBox(height: 2),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: pwdReady ? () => copy(pwdText) : null,
                                child: Text(
                                  !showOneTime
                                      ? '已设置固定密码'
                                      : (_obscurePassword
                                          ? '••••••'
                                          : (pwdText.isEmpty ? '—' : pwdText)),
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: showOneTime ? 20 : 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: showOneTime ? 2 : 0,
                                    height: 1.3,
                                    fontFamily:
                                        showOneTime ? 'monospace' : null,
                                    fontFamilyFallback:
                                        showOneTime ? mono : null,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showOneTime)
                          buildCardIconButton(
                            context: context,
                            onHero: true,
                            icon: _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            tooltip: _obscurePassword
                                ? translate('Show Password')
                                : translate('Hide Password'),
                            onTap: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        if (showOneTime)
                          AnimatedRotationWidget(
                            onPressed: () => bind.mainUpdateTemporaryPassword(),
                            child: Tooltip(
                              message: translate('Refresh Password'),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.refresh_rounded,
                                  size: 19,
                                  color: Colors.white.withOpacity(0.72),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => copy(pwdReady
                              ? '设备 ID：$idText\n临时密码：$pwdText'
                              : idText),
                          child: Container(
                            height: 42,
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.ios_share_rounded,
                                    size: 17, color: Color(0xFF4B3FD1)),
                                const SizedBox(width: 6),
                                Text(
                                  pwdReady ? '复制 ID 和密码' : '复制 ID',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF4B3FD1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  /// Vega 修改：手机扫码——二维码内容与 RustDesk 手机端「扫码导入服务器」格式一致
  /// （config= + ServerConfig.encode()），未自定义时用 Vega 预置中继与公钥。
  void showVegaQrDialog() {
    String opt(String k, String d) {
      final v = bind.mainGetOptionSync(key: k).trim();
      return v.isEmpty ? d : v;
    }

    // 与运行时取值一致：ID 服务器未填用预置；key 仅在自定义 ID 服务器且填了 key 时用自填值，
    // 否则用 Vega 内置公钥（运行时同样回退到内置公钥）；API 地址独立生效。
    const presetHost = '60.205.95.98';
    const presetKey = 'vshoQwJXPQncCbX+1EqpKpqpNp7ZvepyzGVCF2QfbuE=';
    // 与 hbb_common is_official_rendezvous_server 一致：官方 RustDesk 节点视为未设置。
    final savedId = opt('custom-rendezvous-server', '');
    final customId =
        savedId.toLowerCase().contains('rustdesk.com') ? '' : savedId;
    final customKey = opt('key', '');
    // API 地址只保留 scheme://host[:port]/path，去掉账号密码与查询参数，避免泄露凭据。
    String safeApi(String raw) {
      final u = Uri.tryParse(raw);
      if (u == null || !u.hasScheme || u.host.isEmpty) return '';
      return Uri(
              scheme: u.scheme,
              host: u.host,
              port: u.hasPort ? u.port : null,
              path: u.path)
          .toString();
    }

    final data = 'config=' +
        ServerConfig(
          idServer: customId.isNotEmpty ? customId : presetHost,
          relayServer: customId.isNotEmpty
              ? opt('relay-server', '')
              : '$presetHost:21117',
          apiServer: safeApi(opt('api-server', '')),
          key: customId.isNotEmpty && customKey.isNotEmpty
              ? customKey
              : presetKey,
        ).encode();
    gFFI.dialogManager.show((setState, close, context) {
      final palette = VegaColors.of(context);
      return CustomAlertDialog(
        title: const Text('手机扫码，一键配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.separator),
              ),
              child: QrImageView(
                data: data,
                version: QrVersions.auto,
                size: 196,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Color(0xFF2B2378),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Color(0xFF2B2378),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 260,
              child: Text(
                '手机打开 RustDesk → 设置 → ID/中继服务器 → 右上角扫码，扫完即可和这台电脑互联。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: palette.secondary),
              ),
            ),
          ],
        ),
        actions: [dialogButton('OK', onPressed: close)],
        onSubmit: close,
        onCancel: close,
      );
    });
  }

  /// Vega 修改：顶部品牌栏——✦ 标志 + Vega 字标 + 设置。
  Widget buildVegaHeader(BuildContext context) {
    final palette = VegaColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 18, 8),
      child: Row(
        children: [
          const VegaMark(size: 26),
          const SizedBox(width: 10),
          Text(
            'Vega',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: palette.text,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '远程协助',
            style: TextStyle(fontSize: 13, color: palette.secondary),
          ),
          const Spacer(),
          buildPopupMenu(context),
        ],
      ),
    );
  }

  /// 卡片内的小图标按钮（带 hover 反馈）。
  Widget buildCardIconButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool onHero = false,
  }) {
    final palette = VegaColors.of(context);
    final idle = onHero ? Colors.white.withOpacity(0.78) : palette.secondary;
    final active = onHero ? Colors.white : palette.text;
    final RxBool hover = false.obs;
    return Obx(
      () => InkWell(
        onTap: onTap,
        onHover: (value) => hover.value = value,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 20,
              color: hover.value ? active : idle,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context, {bool onHero = false}) {
    final textColor = onHero
        ? Colors.white
        : Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: onHero
                ? Colors.white.withOpacity(hover.value ? 0.28 : 0.16)
                : (hover.value
                    ? Theme.of(context).scaffoldBackgroundColor
                    : Theme.of(context).colorScheme.background),
            child: Icon(
              Icons.settings_outlined,
              size: 19,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildTip(BuildContext context) {
    // Vega 修改：iOS 风格大标题 + 一行中文说明，替换上游 Your Desktop / desk_tip。
    final isOutgoingOnly = bind.isOutgoingOnly();
    final palette = VegaColors.of(context);
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 18.0, bottom: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOutgoingOnly ? '远程控制' : '远程协助',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isOutgoingOnly
                ? translate("outgoing_only_desk_tip")
                : '把 ID 和密码发给对方即可',
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: 12, height: 1.4, color: palette.secondary),
          ),
        ],
      ),
    );
  }


  Widget buildHelpCards(String updateUrl) {
    if (kEnableUpstreamUpdateCheck &&
        !bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          // macOS shows the request prompt only once per app, so later
          // presses would do nothing without opening the settings pane.
          launchUrl(Uri.parse(
              'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    // Vega 修改：安装 / 提示改为一条横幅：图标 + 标题说明 + 右侧小按钮。
    final palette = VegaColors.of(context);
    final showClose = closeButton != null && closeButton == true;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.separator, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: palette.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.shield_outlined, size: 17, color: palette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.isNotEmpty ? translate(title) : vegaCardTitle(content),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                if (content.isNotEmpty)
                  Text(
                    vegaCardBody(content),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: palette.secondary,
                    ),
                  ).marginOnly(top: 2),
              ],
            ),
          ),
          // 上游文档外链关闭（kUpstreamDocsUrl 为空）时不渲染「帮助」入口。
          if (help != null && link != null && kUpstreamDocsUrl.isNotEmpty)
            TextButton(
              onPressed: () async => await launchUrl(Uri.parse(link!)),
              child: Text(
                translate(help),
                style: TextStyle(fontSize: 12, color: palette.accent),
              ),
            ),
          if (btnText.isNotEmpty)
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                btnText == 'Install' ? '安装' : translate(btnText),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ).marginOnly(left: 8),
          if (showClose)
            IconButton(
              icon: Icon(Icons.close, color: palette.secondary, size: 16),
              onPressed: closeCard,
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    // Vega：CI 截图用，VEGA_SHOT_NAV=0/1/2 直接打开对应页面。
    final shotNav = int.tryParse(Platform.environment['VEGA_SHOT_NAV'] ?? '');
    if (shotNav != null && shotNav >= 0 && shotNav <= 2) {
      vegaNavIndex.value = shotNav;
    }
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
          loginMethod: call.arguments['loginMethod'] ?? '',
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}

// Vega 修改：首页提示卡片的中文标题 / 正文（只覆盖 Vega 常见的两种，其余沿用上游翻译）。
String vegaCardTitle(String content) {
  switch (content) {
    case 'install_tip':
    case '':
      return '安装 Vega，让对方随时连得上';
    case 'install_daemon_tip':
      return '安装系统服务';
    default:
      return '提示';
  }
}

String vegaCardBody(String content) {
  switch (content) {
    case 'install_tip':
      return '安装后开机自启、支持无人值守，对方遇到管理员窗口和 UAC 弹窗也能正常操作。';
    default:
      return translate(content);
  }
}
