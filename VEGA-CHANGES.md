# Vega Desktop 相对上游的改动清单

基于 RustDesk，AGPL-3.0 开源，源代码：https://github.com/shisanyue950901-beep/vega-desktop

本文件由 `git diff --name-only main..HEAD` 生成（分支 `vd-p1`）。

## 改动文件

```
flutter/lib/common.dart
flutter/lib/desktop/pages/connection_page.dart
flutter/lib/desktop/pages/desktop_home_page.dart
flutter/lib/desktop/pages/desktop_setting_page.dart
flutter/lib/vega_links.dart
flutter/pubspec.yaml
flutter/windows/CMakeLists.txt
flutter/windows/runner/Runner.rc
libs/hbb_common/src/config.rs
src/auth_2fa.rs
src/client.rs
src/common.rs
src/lang/cn.rs
src/lang/en.rs
```

## 改动概要

- `flutter/lib/vega_links.dart`：新增外链/更新开关常量，集中控制官网、定价、自动更新等入口是否显示。
- `flutter/lib/common.dart`：`checkUpdate` 按开关直接返回，不再请求上游更新服务。
- `flutter/lib/desktop/pages/connection_page.dart`：按开关隐藏公共服务器定价入口，引入 vega_links。
- `flutter/lib/desktop/pages/desktop_home_page.dart`：首页新版本提示 / 自动更新卡片按开关隐藏。
- `flutter/lib/desktop/pages/desktop_setting_page.dart`：设置页 Windows 自动更新与启动检查入口按开关隐藏；关于页的 Website / Privacy Statement 入口改由 `kUpstreamWebsiteUrl` / `kUpstreamPrivacyUrl` 控制（地址为空则不渲染），新增一行 RustDesk/AGPL-3.0 与源码地址说明，该行可点击并打开 `kVegaSourceUrl`。
- `flutter/pubspec.yaml`、`flutter/windows/CMakeLists.txt`、`flutter/windows/runner/Runner.rc`：产品名/可执行文件名与版本资源改为 Vega。
- `libs/hbb_common/src/config.rs`、`src/client.rs`、`src/common.rs`：品牌与上游服务地址相关调整。
- `src/auth_2fa.rs`：2FA 发行方名称改为 Vega。
- `src/lang/cn.rs`、`src/lang/en.rs`：中英文语言包中用户可见名称改为 Vega。

## 保留上游文案的地方

- `upgrade_rustdesk_server_pro_to_{}_tip`（`src/lang/en.rs`、`src/lang/cn.rs`）：仍指上游的 RustDesk Server Pro / 专业版服务器，本 fork 不发行该产品，故不改成 Vega 名称。

## 许可

本项目遵循 AGPL-3.0，与上游 RustDesk 一致；上游版权归其作者所有，见 `LICENCE` 与 `NOTICE-VEGA.md`。
