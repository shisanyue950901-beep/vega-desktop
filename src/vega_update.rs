// Modified for Vega (AGPL-3.0)，新文件
//!
//! 仅检查是否有新版本：读取 Vega 专用 latest.json 并比较版本号。
//! 不下载、不安装、不落盘。
//!
//! 注意：这是新一代 Vega 的专用地址，绝不能用 0.6.x 旧控制台的
//! `/vega/updates/latest.json`。

use hbb_common::{
    anyhow::{anyhow, bail, Context},
    base64::{engine::general_purpose::STANDARD, Engine as _},
    config::LocalConfig,
    log,
    sodiumoxide::{
        self,
        crypto::sign::{verify_detached, PublicKey, Signature},
    },
    ResultType,
};
use serde_derive::Deserialize;
use std::io::Read;
use std::sync::OnceLock;
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

/// Vega 更新专用 Ed25519 公钥（32 字节，base64）。
pub const UPDATE_PUBKEY_B64: &str = "lLXThXxL64J++SDf7KReHhz6XhrpVvHtcaSatxZQ+h8=";

/// 清单里下载地址必须命中以下前缀之一。
const UPDATE_URL_PREFIXES: [&str; 2] = [
    "https://github.com/shisanyue950901-beep/vega-desktop/releases/download/",
    "http://60.205.95.98/vega/desktop/",
];

/// 安装包大小上限：300 MiB。下限为 1 字节。
const MAX_UPDATE_SIZE: u64 = 300 * 1024 * 1024;

/// 防回退记录键：本地已见过的最新清单版本。
const LAST_SEEN_KEY: &str = "vega-update-last-seen";

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
    #[serde(default)]
    pub pub_date: String,
    #[serde(default)]
    pub size: u64,
}

/// 待签名内容：字段按固定顺序拼接，任一处被改都会验签失败。
fn signed_message(m: &VegaManifest) -> String {
    format!(
        "vega-desktop-update\n{}\n{}\n{}\n{}\n{}",
        m.version, m.pub_date, m.url, m.sha256, m.size
    )
}

fn init_sodiumoxide() -> ResultType<()> {
    static INIT: OnceLock<Result<(), String>> = OnceLock::new();
    let result = INIT.get_or_init(|| {
        sodiumoxide::init().map_err(|_| "sodiumoxide 初始化失败".to_string())
    });
    match result {
        Ok(()) => Ok(()),
        Err(err) => Err(anyhow!(err.clone())),
    }
}

fn decode_pubkey() -> ResultType<PublicKey> {
    let raw = STANDARD
        .decode(UPDATE_PUBKEY_B64)
        .context("内置 Vega 更新公钥不是合法 base64")?;
    if raw.len() != 32 {
        bail!("内置 Vega 更新公钥长度不是 32 字节: {}", raw.len());
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&raw);
    Ok(PublicKey(key))
}

fn decode_signature(encoded: &str) -> ResultType<Signature> {
    let raw = STANDARD
        .decode(encoded)
        .context("清单签名不是合法 base64")?;
    if raw.len() != 64 {
        bail!("清单签名长度不是 64 字节: {}", raw.len());
    }
    let mut sig = [0u8; 64];
    sig.copy_from_slice(&raw);
    Signature::from_bytes(&sig).map_err(|_| anyhow!("清单签名字节无效"))
}

/// 校验清单：Ed25519 detached 签名 + 字段约束。任一不满足返回 Err。
fn verify_manifest(m: &VegaManifest) -> ResultType<()> {
    init_sodiumoxide()?;
    let signature = decode_signature(&m.signature)?;
    let pubkey = decode_pubkey()?;

    if m.sha256.len() != 64
        || !m
            .sha256
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        bail!("清单 sha256 不是 64 位小写十六进制: {:?}", m.sha256);
    }
    if m.size == 0 || m.size > MAX_UPDATE_SIZE {
        bail!("清单安装包大小越界: {} 字节", m.size);
    }
    if !UPDATE_URL_PREFIXES.iter().any(|p| m.url.starts_with(*p)) {
        bail!("清单下载地址不在允许的 Vega 发布地址内: {:?}", m.url);
    }

    let message = signed_message(m);
    if !verify_detached(&signature, message.as_bytes(), &pubkey) {
        bail!("清单 Ed25519 签名校验失败: {}", m.version);
    }
    Ok(())
}

/// 本地记录过的最高清单版本（空串表示尚未记录）。
fn last_seen() -> String {
    LocalConfig::get_option(LAST_SEEN_KEY)
}

fn set_last_seen(v: &str) {
    LocalConfig::set_option(LAST_SEEN_KEY.to_owned(), v.to_owned());
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
/// `.no_proxy()`，不读取系统代理，直连镜像；关闭 gzip/zstd 自动解压；
/// 不跟随重定向；请求级 10s 超时（覆盖读完响应体）、5s 连接超时。
/// 构建失败直接返回 Err，由 `fetch_manifest` 转去 GitHub 兜底。
fn fetch_mirror() -> ResultType<VegaManifest> {
    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .no_gzip()
        .no_zstd()
        .connect_timeout(CONNECT_TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .context("创建 Vega 镜像更新检查客户端失败")?;
    let response = client
        .get(MIRROR_URL)
        .timeout(HTTP_TIMEOUT)
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
    if let Err(err) = verify_manifest(&manifest) {
        bail!("镜像清单校验失败，按镜像失败处理: {}", err);
    }
    Ok(manifest)
}

/// GitHub 兜底：reqwest 读取 HTTPS_PROXY / HTTP_PROXY 等环境变量代理，
/// 不读取 Windows 系统代理设置。重定向仅允许 https，最多 5 次，否则中止。
fn fetch_fallback() -> ResultType<VegaManifest> {
    let client = reqwest::blocking::Client::builder()
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() > MAX_REDIRECTS {
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
        .timeout(HTTP_TIMEOUT)
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
    verify_manifest(&manifest)
        .with_context(|| format!("GitHub 清单校验失败: {}", FALLBACK_URL))?;
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
    parse_version(v).is_some() && v.split('.').all(|p| !p.is_empty() && p.len() <= 4)
}

/// 解析版本号：恰好 3 段纯 ASCII 数字（不接受正负号、空白或空段），
/// 逐段转 u32；段数不对或任一段非数字返回 None。
fn parse_version(v: &str) -> Option<(u32, u32, u32)> {
    let mut parts = v.split('.');
    let major = parts.next()?;
    let minor = parts.next()?;
    let patch = parts.next()?;
    if parts.next().is_some() {
        return None;
    }
    let pure_digits = |p: &str| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit());
    if !pure_digits(major) || !pure_digits(minor) || !pure_digits(patch) {
        return None;
    }
    Some((
        major.parse::<u32>().ok()?,
        minor.parse::<u32>().ok()?,
        patch.parse::<u32>().ok()?,
    ))
}

/// 远端版本是否比当前运行版本新：两段都按 (u32, u32, u32) 逐段比较，
/// 任一侧解析失败返回 false。只在 `valid_version` 通过后调用。
fn is_newer(remote: &str) -> bool {
    match (parse_version(remote), parse_version(crate::VERSION)) {
        (Some(remote), Some(current)) => remote > current,
        _ => false,
    }
}

/// 有新版本时返回清单，否则返回 None。
pub fn check() -> ResultType<Option<VegaManifest>> {
    let manifest = fetch_manifest()?;
    if !valid_version(&manifest.version) {
        bail!("远端版本号无效: {:?}", manifest.version);
    }
    let seen = last_seen();
    match parse_version(&seen) {
        Some(seen_version) if parse_version(&manifest.version) < Some(seen_version) => {
            bail!(
                "清单版本回退: 远端 {} 低于本地已见 {}",
                manifest.version,
                seen
            );
        }
        None if !seen.is_empty() => {
            log::warn!("Vega 忽略无法解析的本地已见版本记录: {:?}", seen);
        }
        _ => {}
    }
    if is_newer(&manifest.version) {
        set_last_seen(&manifest.version);
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
