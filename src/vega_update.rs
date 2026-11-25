// Modified for Vega (AGPL-3.0)，新文件
//!
//! 仅检查是否有新版本：读取 Vega 专用 latest.json 并比较版本号。
//! 不下载、不安装、不落盘。
//!
//! 注意：这是新一代 Vega 的专用地址，绝不能用 0.6.x 旧控制台的
//! `/vega/updates/latest.json`。

use hbb_common::{anyhow::Context, log, ResultType};
use serde_derive::Deserialize;
use std::time::Duration;

/// 新一代 Vega 更新清单镜像（国内直连，走 HTTP）。
pub const MIRROR_URL: &str = "http://60.205.95.98/vega/desktop/latest.json";
/// GitHub Releases 上的同一份清单，镜像失败时的兜底。
pub const FALLBACK_URL: &str = "https://github.com/shisanyue950901-beep/vega-desktop/releases/download/vega-desktop-updates/latest.json";

const HTTP_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, Deserialize)]
pub struct VegaManifest {
    pub version: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub sha256: String,
    #[serde(default)]
    pub signature: String,
}

/// 先请求镜像（绕过系统代理），失败再请求 GitHub（走系统代理）。
pub fn fetch_manifest() -> ResultType<VegaManifest> {
    match fetch_mirror() {
        Ok(manifest) => return Ok(manifest),
        Err(err) => {
            log::warn!(
                "Vega 更新检查：镜像 {} 不可用（{}），改用 GitHub",
                MIRROR_URL,
                err
            );
        }
    }
    fetch_fallback()
}

/// 镜像客户端复用仓库现成的 `create_http_client_with_url`：其内部先
/// `.no_proxy()`，即不读取系统代理，符合镜像直连要求。
fn fetch_mirror() -> ResultType<VegaManifest> {
    let client = crate::hbbs_http::create_http_client_with_url(MIRROR_URL);
    let response = client
        .get(MIRROR_URL)
        .timeout(HTTP_TIMEOUT)
        .send()
        .with_context(|| format!("请求镜像失败: {}", MIRROR_URL))?
        .error_for_status()
        .with_context(|| format!("镜像返回错误状态: {}", MIRROR_URL))?;
    response
        .json::<VegaManifest>()
        .with_context(|| format!("解析镜像清单失败: {}", MIRROR_URL))
}

/// GitHub 兜底：reqwest 默认读取系统代理（HTTP_PROXY/HTTPS_PROXY 等）。
fn fetch_fallback() -> ResultType<VegaManifest> {
    let client = reqwest::blocking::Client::builder()
        .timeout(HTTP_TIMEOUT)
        .build()
        .context("创建 GitHub 更新检查客户端失败")?;
    let response = client
        .get(FALLBACK_URL)
        .send()
        .with_context(|| format!("请求 GitHub 清单失败: {}", FALLBACK_URL))?
        .error_for_status()
        .with_context(|| format!("GitHub 返回错误状态: {}", FALLBACK_URL))?;
    response
        .json::<VegaManifest>()
        .with_context(|| format!("解析 GitHub 清单失败: {}", FALLBACK_URL))
}

/// 远端版本是否比当前运行版本新。比较逻辑复用 hbb_common 的
/// `get_version_number`（与 common.rs 里软件更新检查保持一致）。
fn is_newer(remote: &str) -> bool {
    hbb_common::get_version_number(remote) > hbb_common::get_version_number(crate::VERSION)
}

/// 有新版本时返回清单，否则返回 None。
pub fn check() -> ResultType<Option<VegaManifest>> {
    let manifest = fetch_manifest()?;
    if is_newer(&manifest.version) {
        log::info!(
            "Vega 发现新版本: {}（当前 {}）",
            manifest.version,
            crate::VERSION
        );
        Ok(Some(manifest))
    } else {
        log::info!(
            "Vega 已是最新版本: {}（远端 {}）",
            crate::VERSION,
            manifest.version
        );
        Ok(None)
    }
}
