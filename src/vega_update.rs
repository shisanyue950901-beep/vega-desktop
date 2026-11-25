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
    config::Config,
    log,
    sodiumoxide::{
        self,
        crypto::sign::{verify_detached, PublicKey, Signature},
    },
    ResultType,
};
use serde_derive::Deserialize;
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// 新一代 Vega 更新清单镜像（国内直连，走 HTTP）。
pub const MIRROR_URL: &str = "http://60.205.95.98/vega/desktop/latest.json";
/// 镜像源站前缀：命中它的下载地址走直连客户端，其余走 GitHub 客户端。
const MIRROR_ORIGIN: &str = "http://60.205.95.98/";
/// GitHub Releases 上的同一份清单，镜像失败时的兜底。
pub const FALLBACK_URL: &str = "https://github.com/shisanyue950901-beep/vega-desktop/releases/download/vega-desktop-updates/latest.json";

const HTTP_TIMEOUT: Duration = Duration::from_secs(10);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// 安装包下载请求级超时：600 秒，覆盖读完整个响应体。
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(600);
/// 安装包流式读取缓冲区：64 KiB。
const DOWNLOAD_BUF_BYTES: usize = 64 * 1024;
/// 同版本并发下载互斥：从建目录到 rename 全程持锁。
///
/// 临时文件名本身带 pid + 纳秒后缀，锁只负责同一进程内的并发调用
/// 不互相覆盖最终文件；跨进程由 `create_new` 的唯一文件名保证。
static DOWNLOAD_LOCK: Mutex<()> = Mutex::new(());
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

/// 防回退下限文件（独立文件，临时文件 + rename 原子替换）。
const FLOOR_FILE: &str = "vega-update-floor";

/// 待确认安装版本文件：`install` 交出安装包后写入，
/// 下次启动由 [`pending_result`] 读取并删除。
const PENDING_FILE: &str = "vega-update-pending";

/// 保护下限文件的读-改-写，避免并发检查互相覆盖。
static LAST_SEEN_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[derive(Debug, Clone, Deserialize)]
pub struct VegaManifest {
    pub version: String,
    /// 未签名，仅供显示，不可信。
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
    for (name, value) in [
        ("version", &m.version),
        ("pub_date", &m.pub_date),
        ("url", &m.url),
        ("sha256", &m.sha256),
    ] {
        if value.bytes().any(|b| b.is_ascii_control()) {
            bail!("清单 {} 含 ASCII 控制字符: {:?}", name, value);
        }
    }
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
    let Some(prefix) = UPDATE_URL_PREFIXES.iter().find(|p| m.url.starts_with(**p)) else {
        bail!("清单下载地址不在允许的 Vega 发布地址内: {:?}", m.url);
    };
    if ["..", "%", "\\", "?", "#", "@"]
        .iter()
        .any(|p| m.url.contains(p))
        || m.url.chars().any(char::is_whitespace)
    {
        bail!("清单下载地址含不允许的字符: {:?}", m.url);
    }
    let rest = &m.url[prefix.len()..];
    if rest.starts_with('/')
        || rest.contains("//")
        || !rest
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'/' | b'-'))
    {
        bail!("清单下载地址路径不合法: {:?}", m.url);
    }

    let message = signed_message(m);
    if !verify_detached(&signature, message.as_bytes(), &pubkey) {
        bail!("清单 Ed25519 签名校验失败: {}", m.version);
    }
    Ok(())
}

/// 读取本地下限：文件不存在、读取失败或内容无法解析都视为没有下限。
fn read_floor() -> Option<(u32, u32, u32)> {
    let content = std::fs::read_to_string(Config::path(FLOOR_FILE)).ok()?;
    parse_version(content.trim())
}

/// 原子写更新状态文件：同目录写 `tmp_name` 再 rename 覆盖，
/// 任何一步失败都向上返回错误。
fn write_atomic(path: PathBuf, tmp_name: &str, v: &str, what: &str) -> ResultType<()> {
    let dir = match path.parent() {
        Some(dir) if !dir.as_os_str().is_empty() => dir.to_path_buf(),
        _ => bail!("无法确定 {}目录", what),
    };
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("创建 {}目录失败: {}", what, dir.display()))?;
    let tmp = dir.join(tmp_name);
    std::fs::write(&tmp, v.as_bytes())
        .with_context(|| format!("写入 {}临时文件失败: {}", what, tmp.display()))?;
    std::fs::rename(&tmp, &path)
        .with_context(|| format!("替换 {}文件失败: {}", what, path.display()))?;
    Ok(())
}

/// 写本地下限：同目录写 `vega-update-floor.tmp` 再 rename 覆盖。
fn write_floor(v: &str) -> ResultType<()> {
    write_atomic(
        Config::path(FLOOR_FILE),
        "vega-update-floor.tmp",
        v,
        "Vega 更新下限",
    )
}

/// 写待确认安装版本：同目录写 `vega-update-pending.tmp` 再 rename 覆盖。
#[cfg(windows)]
fn write_pending(v: &str) -> ResultType<()> {
    write_atomic(
        Config::path(PENDING_FILE),
        "vega-update-pending.tmp",
        v,
        "Vega 更新待确认",
    )
}

/// 接受清单版本作为新的下限：读取、比较、写入在同一临界区完成。
/// 低于本地下限直接拒绝，高于下限（或尚无下限）则落盘。
fn accept_floor(m: &VegaManifest) -> ResultType<()> {
    let _guard = LAST_SEEN_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(remote) = parse_version(&m.version) else {
        bail!("清单版本无法解析: {:?}", m.version);
    };
    match read_floor() {
        Some(floor) if remote < floor => {
            bail!("清单版本回退（远端 {} 低于本地下限）", m.version)
        }
        Some(floor) if remote == floor => Ok(()),
        _ => write_floor(&m.version),
    }
}

/// 读取并清除上次安装的待确认结果。
///
/// `install` 的 `Ok` 只表示安装包已交给系统安装程序，安装程序会在新进程里
/// 替换并重启 Vega，结果无法跨进程返回；因此交接后会把目标版本原子写入
/// `vega-update-pending`，由下一次启动在这里判定：
/// - 没有待确认文件返回 `None`；
/// - 当前运行版本（与 `is_newer` 同用 `crate::VERSION`）不低于待确认版本，
///   删除文件并返回 `Some(Ok(版本))`；
/// - 否则删除文件并返回 `Some(Err(版本))`，表示更新未生效。
pub fn pending_result() -> Option<Result<String, String>> {
    let path = Config::path(PENDING_FILE);
    let version = match std::fs::read_to_string(&path) {
        Ok(content) => content.trim().to_string(),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return None,
        Err(err) => {
            log::warn!(
                "读取 Vega 更新待确认文件失败 {}: {}",
                path.display(),
                err
            );
            return None;
        }
    };
    if let Err(err) = std::fs::remove_file(&path) {
        if err.kind() != std::io::ErrorKind::NotFound {
            log::warn!(
                "删除 Vega 更新待确认文件失败 {}: {}",
                path.display(),
                err
            );
        }
    }
    let applied = match (parse_version(&version), parse_version(crate::VERSION)) {
        (Some(pending), Some(current)) => current >= pending,
        _ => false,
    };
    if applied {
        log::info!("Vega 更新已生效: {}", version);
        Some(Ok(version))
    } else {
        log::warn!(
            "Vega 更新未生效（待确认 {}，当前 {}）",
            version,
            crate::VERSION
        );
        Some(Err(version))
    }
}

/// 先请求镜像（绕过系统代理），失败再请求 GitHub（走环境变量代理）。
fn fetch_manifest() -> ResultType<VegaManifest> {
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

/// 镜像客户端：不复用仓库 hbbs_http 的现成客户端，自建客户端并
/// `.no_proxy()`，不读取系统代理，直连镜像；关闭 gzip/zstd 自动解压；
/// 不跟随重定向；5s 连接超时。清单检查和安装包下载共用。
fn mirror_client() -> ResultType<reqwest::blocking::Client> {
    reqwest::blocking::Client::builder()
        .no_proxy()
        .no_gzip()
        .no_zstd()
        .connect_timeout(CONNECT_TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .context("创建 Vega 镜像更新客户端失败")
}

/// 镜像清单检查：请求级 10s 超时（覆盖读完响应体）；构建客户端失败
/// 直接返回 Err，由 `fetch_manifest` 转去 GitHub 兜底。
fn fetch_mirror() -> ResultType<VegaManifest> {
    let client = mirror_client()?;
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
    accept_floor(&manifest).context("镜像清单版本下限未通过，按镜像失败处理")?;
    Ok(manifest)
}

/// GitHub 客户端：reqwest 读取 HTTPS_PROXY / HTTP_PROXY 等环境变量代理，
/// 不读取 Windows 系统代理设置。重定向仅允许 https，最多 5 次，否则中止。
/// 清单检查和安装包下载共用。
fn github_client() -> ResultType<reqwest::blocking::Client> {
    reqwest::blocking::Client::builder()
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() > MAX_REDIRECTS {
                attempt.error("GitHub 重定向次数超过 5 次")
            } else if attempt.url().scheme() != "https" {
                attempt.error("GitHub 重定向目标不是 HTTPS")
            } else {
                attempt.follow()
            }
        }))
        .build()
        .context("创建 GitHub 更新客户端失败")
}

/// GitHub 兜底清单检查：请求级 10s 超时。
fn fetch_fallback() -> ResultType<VegaManifest> {
    let client = github_client()?;
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
    accept_floor(&manifest)
        .with_context(|| format!("GitHub 清单版本下限未通过: {}", FALLBACK_URL))?;
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

/// 安装包的最终落盘路径：`%TEMP%/VegaUpdate/Vega-Setup-<version>.exe`。
///
/// `download` 用它决定 rename 目标，`install` 用它核对调用方给的路径，
/// 两处共用同一个计算，保证装的就是刚下载的那一个文件。
fn final_installer_path(version: &str) -> ResultType<PathBuf> {
    if !valid_version(version) {
        bail!("清单版本号无效，拒绝用于安装包文件名: {:?}", version);
    }
    Ok(std::env::temp_dir()
        .join("VegaUpdate")
        .join(format!("Vega-Setup-{}.exe", version)))
}

/// 下载安装包并校验，只落盘，不安装、不执行。
///
/// 1. 再次 `verify_manifest`（签名、地址、大小、哈希格式都重查一遍）；
/// 2. 取 `DOWNLOAD_LOCK` 后建目录 `%TEMP%/VegaUpdate`，用 `create_new`
///    创建带 pid + 纳秒后缀的
///    `Vega-Setup-<version>.<pid>-<nanos>.part`，同名文件已存在即失败；
/// 3. 镜像地址用直连客户端、GitHub 地址用仅 HTTPS 重定向客户端，
///    请求级 600s 超时，状态码必须成功；
/// 4. 64 KiB 缓冲区流式写盘并同步更新 SHA-256，累计字节超过清单大小
///    立即中止；结束后字节数与哈希都必须与清单一致；
/// 5. 全部通过才 `rename` 成最终文件名，直接覆盖已存在的旧安装包
///    （Windows 上 rename 会替换目标）；失败只删本次的 `.part`，不动旧文件。
///    只有本次调用成功 `create_new` 的 `.part` 才会被清理，建目录前的错误
///    不删文件。
pub fn download(m: &VegaManifest) -> ResultType<PathBuf> {
    verify_manifest(m)?;
    let final_path = final_installer_path(&m.version)?;

    // 同版本并发下载互斥，直到 rename 完成才释放；锁中毒也继续用内部值。
    let _guard = DOWNLOAD_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    // `.part` 与最终安装包同目录：目录从 final_installer_path 推导，
    // 不再单独拼一次 temp_dir()。
    let dir = match final_path.parent() {
        Some(dir) if !dir.as_os_str().is_empty() => dir.to_path_buf(),
        _ => bail!("无法确定 Vega 更新下载目录"),
    };
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos())
        .unwrap_or(0);
    let part_path = dir.join(format!(
        "Vega-Setup-{}.{}-{}.part",
        m.version,
        std::process::id(),
        nanos
    ));

    // 建目录失败时本次还没有创建 `.part`，不删除任何文件。
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("创建 Vega 更新下载目录失败 {}", dir.display()))?;

    // `create_new`：同名临时文件已存在（并发或残留）直接失败，绝不覆盖。
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&part_path)
        .with_context(|| format!("创建安装包临时文件失败: {}", part_path.display()))?;

    // 从这里开始 `.part` 属于本次调用，后续失败才允许删除。
    if let Err(err) = download_to(m, &part_path, file) {
        remove_part(&part_path);
        return Err(err);
    }
    // 直接 rename 覆盖旧安装包：先删旧文件会在 rename 失败时把已有安装包
    // 也一起丢掉。Windows 上 rename 目标已存在时会替换。
    if let Err(err) = std::fs::rename(&part_path, &final_path) {
        remove_part(&part_path);
        return Err(anyhow!(
            "替换安装包文件失败 {} -> {}: {}",
            part_path.display(),
            final_path.display(),
            err
        ));
    }
    log::info!(
        "Vega 安装包已下载并校验: {}（{} 字节）",
        final_path.display(),
        m.size
    );
    Ok(final_path)
}

/// 删除 `.part` 临时文件；文件本就不存在不算失败。
fn remove_part(part: &Path) {
    if let Err(err) = std::fs::remove_file(part) {
        if err.kind() != std::io::ErrorKind::NotFound {
            log::warn!("删除 Vega 安装包临时文件失败 {}: {}", part.display(), err);
        }
    }
}

/// 下载并校验到已由 `download` 用 `create_new` 建好的 `part` / `file`。
/// 失败清理和成功后 rename 由 `download` 负责。
fn download_to(m: &VegaManifest, part: &Path, mut file: std::fs::File) -> ResultType<()> {
    let client = if m.url.starts_with(MIRROR_ORIGIN) {
        mirror_client()?
    } else {
        github_client()?
    };
    let mut response = client
        .get(m.url.as_str())
        .timeout(DOWNLOAD_TIMEOUT)
        .send()
        .with_context(|| format!("请求安装包失败: {}", m.url))?;
    if !response.status().is_success() {
        bail!("下载安装包返回错误状态 {}: {}", response.status(), m.url);
    }

    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; DOWNLOAD_BUF_BYTES];
    let mut total: u64 = 0;
    loop {
        let n = response
            .read(&mut buf)
            .with_context(|| format!("读取安装包数据失败: {}", m.url))?;
        if n == 0 {
            break;
        }
        total += n as u64;
        if total > m.size {
            bail!(
                "安装包超过清单声明大小（>{} 字节），已中止: {}",
                m.size,
                m.url
            );
        }
        file.write_all(&buf[..n])
            .with_context(|| format!("写入安装包临时文件失败: {}", part.display()))?;
        hasher.update(&buf[..n]);
    }
    file.flush()
        .with_context(|| format!("刷新安装包临时文件失败: {}", part.display()))?;
    drop(file);

    if total != m.size {
        bail!(
            "安装包大小与清单不符（实际 {}，清单 {}）: {}",
            total,
            m.size,
            m.url
        );
    }
    let digest = hex::encode(hasher.finalize());
    if digest != m.sha256 {
        bail!(
            "安装包 SHA-256 与清单不符（实际 {}，清单 {}）: {}",
            digest,
            m.sha256,
            m.url
        );
    }
    Ok(())
}

/// 安装已下载并校验过的 Vega 安装包（仅 Windows）。
///
/// 只装已签名校验过的包：先重新 `verify_manifest`（签名、地址、大小、
/// 哈希格式全部重查），再要求 `path` 与 [`download`] 的最终落盘路径
/// 完全一致，然后把路径交给 `crate::platform::update_to_verified`——
/// 它负责复制到受保护位置、重新核对 SHA-256 与大小、UAC 提权一次，
/// 并以 `--update` 静默覆盖安装后重启。
///
/// UAC 提权只弹一次；用户在 UAC 对话框点“取消”时返回 `Err`，
/// 本函数不退出程序，调用方可以继续运行旧版本。
///
/// `Ok` 只表示安装包已交给系统安装程序，不代表安装成功：安装程序会在
/// 新进程里替换并重启 Vega，结果无法跨进程返回。交接后会把 `m.version`
/// 原子写入 `vega-update-pending`，重启后由 [`pending_result`] 判断更新
/// 是否真的生效。
#[cfg(windows)]
pub fn install(m: &VegaManifest, path: &std::path::Path) -> ResultType<()> {
    verify_manifest(m).context("安装前重新校验 Vega 清单失败")?;
    if !is_newer(&m.version) {
        bail!(
            "清单版本 {} 不高于当前运行版本 {}，拒绝安装",
            m.version,
            crate::VERSION
        );
    }
    let remote = parse_version(&m.version)
        .ok_or_else(|| anyhow!("清单版本无法解析，拒绝安装: {:?}", m.version))?;
    if let Some(floor) = read_floor() {
        if remote < floor {
            bail!(
                "清单版本回退（远端 {} 低于本地下限 {}.{}.{}），拒绝安装",
                m.version,
                floor.0,
                floor.1,
                floor.2
            );
        }
    }
    let expected = final_installer_path(&m.version).context("计算 Vega 安装包最终路径失败")?;
    if path != expected {
        bail!(
            "安装包路径与下载路径不一致（期望 {}，实际 {}）",
            expected.display(),
            path.display()
        );
    }
    let Some(path_str) = path.to_str() else {
        bail!("安装包路径不是合法 UTF-8: {}", path.display());
    };
    crate::platform::update_to_verified(path_str, &m.sha256, m.size).with_context(|| {
        format!(
            "启动 Vega 安装包失败（UAC 被取消或安装未完成）: {}",
            path.display()
        )
    })?;
    log::info!("Vega 安装包已交给系统提权安装: {}", path.display());
    write_pending(&m.version).context("记录 Vega 更新待确认版本失败")?;
    Ok(())
}
