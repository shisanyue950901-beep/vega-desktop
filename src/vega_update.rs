// Modified for Vega (AGPL-3.0)，新文件
//!
//! 仅检查是否有新版本：读取 Vega 专用 latest.json 并比较版本号。
//! 不下载、不安装、不落盘。
//!
//! 注意：这是新一代 Vega 的专用地址，绝不能用 0.6.x 旧控制台的
//! `/vega/updates/latest.json`。

use hbb_common::{anyhow::bail, anyhow::Context, log, ResultType};
use serde_derive::Deserialize;
use std::io::Read;
use std::time::Duration;

/// 新一代 Vega 更新清单镜像（国内直连，走 HTTP）。
pub const MIRROR_URL: &str = "http://60.205.95.98/vega/desktop/latest.json";
/// GitHub Releases 上的同一份清单，镜像失败时的兜底。
pub const FALLBACK_URL: &str = "https://github.com/shisanyue950901-beep/vega-desktop/releases/download/vega-desktop-updates/latest.json";

const HTTP_TIMEOUT: Duration = Duration::from_secs(10);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// 清单响应体上限：64 KiB。超过即视为异常响应。
const MAX_BODY_BYTES: usize = 64 * 1024;
/// GitHub 兜底最多跟随 5 次重定向。
const MAX_REDIRECTS: usize = 5;

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

/// 先请求镜像（绕过系统代理），失败再请求 GitHub（走环境变量代理）。
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

/// 镜像客户端不复用仓库 hbbs_http 的现成客户端：自建客户端并
/// `.no_proxy()`，不读取系统代理，直连镜像；不跟随重定向；
/// 10s 总超时、5s 连接超时。构建失败直接返回 Err，由 `fetch_manifest`
/// 转去 GitHub 兜底。
fn fetch_mirror() -> ResultType<VegaManifest> {
    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .timeout(HTTP_TIMEOUT)
        .connect_timeout(CONNECT_TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .context("创建 Vega 镜像更新检查客户端失败")?;
    let response = client
        .get(MIRROR_URL)
        .send()
        .with_context(|| format!("请求镜像失败: {}", MIRROR_URL))?;
    if !response.status().is_success() {
        bail!("镜像返回错误状态 {}: {}", response.status(), MIRROR_URL);
    }
    let manifest = read_manifest(response, MIRROR_URL)?;
    if !valid_version(&manifest.version) {
        bail!(
            "镜像清单版本号无效 {:?}，按镜像失败处理: {}",
            manifest.version,
            MIRROR_URL
        );
    }
    Ok(manifest)
}

/// GitHub 兜底：reqwest 读取 HTTPS_PROXY / HTTP_PROXY 等环境变量代理，
/// 不读取 Windows 系统代理设置。重定向仅允许 https，最多 5 次，否则中止。
fn fetch_fallback() -> ResultType<VegaManifest> {
    let client = reqwest::blocking::Client::builder()
        .timeout(HTTP_TIMEOUT)
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() >= MAX_REDIRECTS {
                attempt.error("GitHub 清单重定向次数超过 5 次")
            } else if attempt.url().scheme() != "https" {
                attempt.error("GitHub 清单重定向目标不是 HTTPS")
            } else {
                attempt.follow()
            }
        }))
        .build()
        .context("创建 GitHub 更新检查客户端失败")?;
    let response = client
        .get(FALLBACK_URL)
        .send()
        .with_context(|| format!("请求 GitHub 清单失败: {}", FALLBACK_URL))?;
    if !response.status().is_success() {
        bail!(
            "GitHub 返回错误状态 {}: {}",
            response.status(),
            FALLBACK_URL
        );
    }
    let manifest = read_manifest(response, FALLBACK_URL)?;
    if !valid_version(&manifest.version) {
        bail!("GitHub 清单版本号无效: {:?}", manifest.version);
    }
    Ok(manifest)
}

/// 限量读取响应体（最多 64 KiB）再解析：`take(65537)` 多读 1 字节用于
/// 判断是否超限；超限、读失败、解析失败都带上来源 URL 返回 Err。
fn read_manifest(response: reqwest::blocking::Response, url: &str) -> ResultType<VegaManifest> {
    let mut buf = Vec::with_capacity(MAX_BODY_BYTES);
    response
        .take(MAX_BODY_BYTES as u64 + 1)
        .read_to_end(&mut buf)
        .with_context(|| format!("读取清单响应失败: {}", url))?;
    if buf.len() > MAX_BODY_BYTES {
        bail!("清单响应体超过 {} 字节上限: {}", MAX_BODY_BYTES, url);
    }
    serde_json::from_slice::<VegaManifest>(&buf).with_context(|| format!("解析清单失败: {}", url))
}

/// 版本号必须恰好 3 段，以 '.' 分隔，每段 1–4 位纯 ASCII 数字（如 1.5.3）。
fn valid_version(v: &str) -> bool {
    let parts: Vec<&str> = v.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 4 && p.bytes().all(|b| b.is_ascii_digit()))
}

/// 远端版本是否比当前运行版本新。比较逻辑复用 hbb_common 的
/// `get_version_number`（与 common.rs 里软件更新检查保持一致）。
/// 只在 `valid_version` 通过后调用。
fn is_newer(remote: &str) -> bool {
    hbb_common::get_version_number(remote) > hbb_common::get_version_number(crate::VERSION)
}

/// 有新版本时返回清单，否则返回 None。
pub fn check() -> ResultType<Option<VegaManifest>> {
    let manifest = fetch_manifest()?;
    if !valid_version(&manifest.version) {
        bail!("远端版本号无效: {:?}", manifest.version);
    }
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
