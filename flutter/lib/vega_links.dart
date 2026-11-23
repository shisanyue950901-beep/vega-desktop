import 'package:url_launcher/url_launcher.dart';

/// Vega fork 外链开关。
///
/// 本 fork 不再访问上游 RustDesk 官方站点：官网、文档、下载、定价、隐私
/// 声明、GitHub release/changelog 一律留空。UI 代码保持原样，只读取这些
/// 常量；需要恢复时把对应值改回上游 URL 即可。
///
/// AGPL-3.0 §5a 署名信息见仓库根 VEGA-CHANGES.md。
const String kVegaSourceUrl =
    'https://github.com/shisanyue950901-beep/vega-desktop';

/// 上游官方外链：全部关闭。
const String kUpstreamWebsiteUrl = '';
const String kUpstreamDocsUrl = '';
const String kUpstreamDownloadUrl = '';
const String kUpstreamPricingUrl = '';
const String kUpstreamPrivacyUrl = '';
const String kUpstreamReleaseUrl = '';
const String kUpstreamChangelogUrl = '';

/// 上游版本检查 / 自动更新开关（与 src/common.rs 的
/// `ENABLE_UPSTREAM_UPDATE_CHECK` 对应）：关闭时所有更新入口不渲染，
/// 功能代码保持不动。
const bool kEnableUpstreamUpdateCheck = false;

/// 本 fork 的依据与许可，用于「关于」页展示。
const String kVegaLicenseName = 'AGPL-3.0';
const String kVegaUpstreamName = 'RustDesk';
const String kVegaAboutLine =
    '基于 RustDesk，AGPL-3.0 开源，源代码：$kVegaSourceUrl';

/// 统一的安全打开入口：空串直接返回，避免打开 about:blank 或抛异常。
Future<void> openVegaLink(String url) async {
  if (url.isEmpty) {
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return;
  }
  try {
    await launchUrl(uri);
  } catch (_) {}
}
