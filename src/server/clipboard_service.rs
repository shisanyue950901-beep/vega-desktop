use super::*;
#[cfg(not(target_os = "android"))]
use crate::clipboard::clipboard_listener::{self, ClipboardEvent};
#[cfg(not(target_os = "android"))]
pub use crate::clipboard::{ClipboardContext, ClipboardSide};
pub use crate::clipboard::{CLIPBOARD_INTERVAL as INTERVAL, CLIPBOARD_NAME as NAME};
#[cfg(windows)]
use crate::ipc::{self, ClipboardFile, ClipboardNonFile, Data};
#[cfg(feature = "unix-file-copy-paste")]
pub use crate::{
    clipboard::{check_clipboard_files, FILE_CLIPBOARD_NAME as FILE_NAME},
    clipboard_file::unix_file_clip,
};
#[cfg(target_os = "android")]
use base::config::keys;
#[cfg(all(feature = "unix-file-copy-paste", target_os = "linux"))]
use clipboard::platform::unix::fuse::{init_fuse_context, uninit_fuse_context};
#[cfg(target_os = "android")]
use hbb_common::config::option2bool;
#[cfg(target_os = "android")]
use std::sync::atomic::{AtomicBool, Ordering};
use std::{
    io,
    sync::mpsc::{channel, RecvTimeoutError},
    time::Duration,
};
#[cfg(windows)]
use tokio::runtime::Runtime;

#[cfg(target_os = "android")]
static CLIPBOARD_SERVICE_OK: AtomicBool = AtomicBool::new(false);

#[cfg(not(target_os = "android"))]
struct Handler {
    ctx: Option<ClipboardContext>,
    #[cfg(target_os = "windows")]
    stream: Option<ipc::ConnectionTmpl<parity_tokio_ipc::ConnectionClient>>,
    #[cfg(target_os = "windows")]
    rt: Option<Runtime>,
}

#[cfg(target_os = "android")]
pub fn is_clipboard_service_ok() -> bool {
    CLIPBOARD_SERVICE_OK.load(Ordering::SeqCst)
}

pub fn new(name: String) -> GenericService {
    let svc = EmptyExtraFieldService::new(name, false);
    GenericService::run(&svc.clone(), run);
    svc.sp
}

#[cfg(not(target_os = "android"))]
fn run(sp: EmptyExtraFieldService) -> ResultType<()> {
    #[cfg(all(feature = "unix-file-copy-paste", target_os = "linux"))]
    let _fuse_call_on_ret = {
        if sp.name() == FILE_NAME {
            Some(init_fuse_context(false).map(|_| crate::SimpleCallOnReturn {
                b: true,
                f: Box::new(|| {
                    uninit_fuse_context(false);
                }),
            }))
        } else {
            None
        }
    };

    let (tx_cb_result, rx_cb_result) = channel();
    let ctx = Some(ClipboardContext::new().map_err(|e| io::Error::new(io::ErrorKind::Other, e))?);
    clipboard_listener::subscribe(sp.name(), tx_cb_result)?;
    let mut handler = Handler {
        ctx,
        #[cfg(target_os = "windows")]
        stream: None,
        #[cfg(target_os = "windows")]
        rt: None,
    };

    while sp.ok() {
        match rx_cb_result.recv_timeout(Duration::from_millis(INTERVAL)) {
            Ok(ClipboardEvent::Changed) => {
                #[cfg(feature = "unix-file-copy-paste")]
                if sp.name() == FILE_NAME {
                    handler.check_clipboard_file();
                    continue;
                }
                if let Some(msg) = handler.get_clipboard_msg() {
                    sp.send(msg);
                }
            }
            // Host startup state must not supersede a client's explicit initial snapshot.
            #[cfg(all(target_os = "linux", feature = "unix-file-copy-paste"))]
            Ok(ClipboardEvent::InitialSelection) => {}
            Ok(ClipboardEvent::Stop) => {
                log::debug!("Clipboard listener stopped");
                break;
            }
            Ok(ClipboardEvent::StopWithError(err)) => {
                bail!("Clipboard listener stopped with error: {}", err);
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                log::error!("Clipboard listener disconnected");
                break;
            }
        }
    }

    clipboard_listener::unsubscribe(&sp.name());

    Ok(())
}

#[cfg(target_os = "linux")]
const WAYLAND_CLIPBOARD_SKIP_CHECK_MAX_UTF8_BYTES: usize =
    super::input_service::WAYLAND_CLIPBOARD_INPUT_MAX_TEXT_CHARS * 4;

#[cfg(target_os = "linux")]
fn decode_utf8_prefix(bytes: &[u8]) -> Option<String> {
    let end = bytes.len().min(WAYLAND_CLIPBOARD_SKIP_CHECK_MAX_UTF8_BYTES);
    let slice = &bytes[..end];
    match std::str::from_utf8(slice) {
        Ok(text) => Some(text.to_owned()),
        Err(e) => {
            if e.error_len().is_some() {
                return None;
            }
            let valid_up_to = e.valid_up_to();
            std::str::from_utf8(&slice[..valid_up_to])
                .ok()
                .map(ToOwned::to_owned)
        }
    }
}

#[cfg(target_os = "linux")]
fn decode_text_clipboard(clipboard: &Clipboard) -> Option<String> {
    if clipboard.format.enum_value() != Ok(ClipboardFormat::Text) {
        return None;
    }
    if clipboard.compress {
        let bytes = hbb_common::compress::decompress(&clipboard.content);
        return decode_utf8_prefix(&bytes);
    }
    decode_utf8_prefix(&clipboard.content)
}

#[cfg(target_os = "linux")]
fn should_skip_wayland_clipboard_sync(msg: &Message) -> bool {
    if crate::platform::linux::is_x11() {
        return false;
    }
    let is_recent_wayland_input = |clipboard: &Clipboard| -> bool {
        let Some(text) = decode_text_clipboard(clipboard) else {
            return false;
        };
        super::input_service::is_recent_wayland_clipboard_input(&text)
    };

    match &msg.union {
        Some(message::Union::Clipboard(clipboard)) => is_recent_wayland_input(clipboard),
        Some(message::Union::MultiClipboards(multi_clipboards)) => multi_clipboards
            .clipboards
            .iter()
            .any(is_recent_wayland_input),
        _ => false,
    }
}

#[cfg(not(target_os = "android"))]
impl Handler {
    #[cfg(feature = "unix-file-copy-paste")]
    fn check_clipboard_file(&mut self) {
        if let Some(urls) = check_clipboard_files(&mut self.ctx, ClipboardSide::Host, false) {
            if !urls.is_empty() {
                #[cfg(target_os = "macos")]
                if crate::clipboard::is_file_url_set_by_rustdesk(&urls) {
                    return;
                }
                match clipboard::platform::unix::serv_files::sync_files(&urls) {
                    Ok(()) => {
                        // Use `send_data()` here to reuse `handle_file_clip()` in `connection.rs`.
                        hbb_common::allow_err!(clipboard::send_data(
                            0,
                            unix_file_clip::get_format_list()
                        ));
                    }
                    Err(e) => {
                        log::error!("Failed to sync clipboard files: {}", e);
                    }
                }
            }
        }
    }

    fn get_clipboard_msg(&mut self) -> Option<Message> {
        #[cfg(target_os = "windows")]
        if crate::common::is_server() && crate::platform::is_root() {
            match self.read_clipboard_from_cm_ipc() {
                Err(e) => {
                    log::error!("Failed to read clipboard from cm: {}", e);
                }
                Ok(data) => {
                    // Skip sending empty clipboard data.
                    // Maybe there's something wrong reading the clipboard data in cm, but no error msg is returned.
                    // The clipboard data should not be empty, the last line will try again to get the clipboard data.
                    if !data.is_empty() {
                        let mut msg = Message::new();
                        let multi_clipboards = MultiClipboards {
                            clipboards: data
                                .into_iter()
                                .map(|c| Clipboard {
                                    compress: c.compress,
                                    content: c.content,
                                    width: c.width,
                                    height: c.height,
                                    format: ClipboardFormat::from_i32(c.format)
                                        .unwrap_or(ClipboardFormat::Text)
                                        .into(),
                                    special_name: c.special_name,
                                    ..Default::default()
                                })
                                .collect(),
                            ..Default::default()
                        };
                        msg.set_multi_clipboards(multi_clipboards);
                        return Some(msg);
                    }
                }
            }
        }

        #[cfg(target_os = "linux")]
        {
            let msg = crate::clipboard::peek_clipboard(&mut self.ctx, ClipboardSide::Host, false)?;
            if should_skip_wayland_clipboard_sync(&msg) {
                log::debug!("Skip clipboard sync for recent Wayland keyboard injection");
                return None;
            }
            return Some(msg);
        }
        #[cfg(not(target_os = "linux"))]
        {
            crate::clipboard::check_clipboard(&mut self.ctx, ClipboardSide::Host, false)
        }
    }

    // Read clipboard data from cm using ipc.
    //
    // We cannot use `#[tokio::main(flavor = "current_thread")]` here,
    // because the auto-managed tokio runtime (async context) will be dropped after the call.
    // The next call will create a new runtime, which will cause the previous stream to be unusable.
    // So we need to manage the tokio runtime manually.
    // Vega 修改：单次读取；超时或意外帧一律丢弃 stream 并返回 Err，避免迟到的旧回复被下一次读取误用。
    // `deadline` 是整次读取（含外层最多一次重试）共用的总截止时间；
    // `allow_reconnect` 为 false 时，本函数不再「旧 stream 发送失败就换新连接」，
    // 只能在外层已清空 stream 的前提下新建一个连接。
    // `reconnected` 回传本次调用是否新建过连接，供外层判断还能不能重试。
    #[cfg(windows)]
    fn read_clipboard_from_cm_ipc_once(
        &mut self,
        deadline: std::time::Instant,
        allow_reconnect: bool,
        reconnected: &mut bool,
    ) -> ResultType<Vec<ClipboardNonFile>> {
        if self.rt.is_none() {
            self.rt = Some(Runtime::new()?);
        }
        let Some(rt) = &self.rt else {
            // unreachable!
            bail!("failed to get tokio runtime");
        };
        let mut is_sent = false;
        // Vega 修改：到点直接放弃，不再尝试发送（放在借用 stream 之前清空，避免借用冲突）。
        let send_remaining = cm_ipc_remaining_ms(deadline);
        if send_remaining == 0 {
            self.stream = None;
            bail!("timed out sending clipboard request to cm");
        }
        if let Some(stream) = &mut self.stream {
            // If previous stream is still alive, reuse it.
            // If the previous stream is dead, `is_sent` will trigger reconnect.
            // Vega 修改：发送请求同样受总截止时间约束，超时视为发送失败。
            is_sent = match rt.block_on(async {
                timeout(send_remaining, stream.send(&Data::ClipboardNonFile(None))).await
            }) {
                Ok(Ok(_)) => true,
                Ok(Err(e)) => {
                    log::trace!("Failed to send to cm: {}", e);
                    false
                }
                Err(e) => {
                    log::trace!("Failed to send to cm: {}", e);
                    false
                }
            };
        }
        if !is_sent {
            if self.stream.is_some() && !allow_reconnect {
                self.stream = None;
                bail!("failed to send clipboard request to cm");
            }
            // Vega 修改：建连同样受总截止时间约束，剩余为 0 直接放弃。
            let connect_remaining = cm_ipc_remaining_ms(deadline);
            if connect_remaining == 0 {
                self.stream = None;
                bail!("timed out connecting to cm");
            }
            let connect_result =
                rt.block_on(crate::ipc::connect(connect_remaining.min(100), "_cm"));
            let mut stream = match connect_result {
                Ok(stream) => stream,
                Err(e) => {
                    self.stream = None;
                    return Err(e);
                }
            };
            // Vega 修改：连接成功后立刻置位，保证一次读取最多新建一条连接（首次发送失败也不再重连）。
            *reconnected = true;
            // Vega 修改：新连接的首次发送同样受总截止时间约束，超时视为失败。
            let first_send_remaining = cm_ipc_remaining_ms(deadline);
            if first_send_remaining == 0 {
                self.stream = None;
                bail!("timed out sending clipboard request to cm");
            }
            let sent = rt.block_on(async {
                timeout(
                    first_send_remaining,
                    stream.send(&Data::ClipboardNonFile(None)),
                )
                .await
            });
            match sent {
                Ok(Ok(_)) => {}
                Ok(Err(e)) => {
                    log::trace!("Failed to send to cm: {}", e);
                    self.stream = None;
                    bail!("failed to send clipboard request to cm");
                }
                Err(e) => {
                    log::trace!("Failed to send to cm: {}", e);
                    self.stream = None;
                    bail!("timed out sending clipboard request to cm: {}", e);
                }
            }
            self.stream = Some(stream);
        }

        // Vega 修改：每轮单独短借用 stream，超时/出错时可以安全清空 self.stream 再报错。
        loop {
            // Vega 修改：每轮都按总截止时间算剩余时间，剩余为 0 就放弃并丢弃 stream。
            let remaining = cm_ipc_remaining_ms(deadline);
            if remaining == 0 {
                self.stream = None;
                bail!("timed out getting clipboard data from cm");
            }
            let next = {
                let Some(stream) = self.stream.as_mut() else {
                    bail!("failed to get clipboard data from cm");
                };
                rt.block_on(stream.next_timeout(remaining.min(800)))
            };
            // Vega 修改：next_timeout 出错时清掉 stream，不能让旧回复留在缓冲区。
            let data = match next {
                Ok(data) => data,
                Err(e) => {
                    self.stream = None;
                    bail!("failed to get clipboard data from cm: {}", e);
                }
            };
            match data {
                Some(Data::ClipboardNonFile(Some((err, mut contents)))) => {
                    if !err.is_empty() {
                        bail!("{}", err);
                    } else {
                        if contents.iter().any(|c| c.next_raw) {
                            // Wrap the future with a `Timeout` in an async block to avoid panic.
                            // We cannot use `rt.block_on(timeout(1000, stream.next_raw()))` here, because it causes panic:
                            // thread '<unnamed>' panicked at D:\Projects\rust\rustdesk\libs\hbb_common\src\lib.rs:98:5:
                            // there is no reactor running, must be called from the context of a Tokio 1.x runtime
                            // note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
                            // Vega 修改：raw 数据的等待同样不能超过总截止时间。
                            let raw_wait = cm_ipc_remaining_ms(deadline).min(1000);
                            if raw_wait == 0 {
                                self.stream = None;
                                bail!("timed out getting raw clipboard data from cm");
                            }
                            let raw = {
                                let Some(stream) = self.stream.as_mut() else {
                                    bail!("failed to get clipboard data from cm");
                                };
                                rt.block_on(async {
                                    timeout(raw_wait, stream.next_raw()).await
                                })
                            };
                            match raw {
                                Ok(Ok(mut data)) => {
                                    for c in &mut contents {
                                        if c.next_raw {
                                            // No need to check the length because sum(content_len) == data.len().
                                            c.content = data.split_to(c.content_len).into();
                                        }
                                    }
                                }
                                Ok(Err(e)) => {
                                    // reset by peer
                                    self.stream = None;
                                    bail!("failed to get raw clipboard data: {}", e);
                                }
                                Err(e) => {
                                    // Vega 修改：超时同样丢弃 stream 并报错，不再返回带空占位的内容。
                                    self.stream = None;
                                    bail!("failed to get raw clipboard data: {}", e);
                                }
                            }
                        }
                        return Ok(contents);
                    }
                }
                Some(Data::ClipboardFile(ClipboardFile::MonitorReady)) => {
                    // ClipboardFile::MonitorReady is the first message sent by cm.
                }
                _ => {
                    // Vega 修改：收到非 ClipboardNonFile 的意外帧，丢弃 stream 后报错。
                    self.stream = None;
                    bail!("failed to get clipboard data from cm");
                }
            }
        }
        // unreachable!
        bail!("failed to get clipboard data from cm");
    }

    // Vega 修改：整次读取（含最多一次重试）共用 1500ms 总截止时间；
    // 一次读取最多新建一个连接：第一次尝试内部已经新建过连接就不再重试，
    // 否则清空 stream 后用 allow_reconnect=false 再试一次，该次只允许新建一个连接。
    #[cfg(windows)]
    fn read_clipboard_from_cm_ipc(&mut self) -> ResultType<Vec<ClipboardNonFile>> {
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(1500);
        let mut reconnected = false;
        match self.read_clipboard_from_cm_ipc_once(deadline, true, &mut reconnected) {
            Ok(contents) => Ok(contents),
            Err(e) => {
                // 第一次尝试内已经新建过连接，再试就可能新建第二个连接，直接失败。
                if reconnected {
                    log::trace!(
                        "Failed to read clipboard from cm: {}, already reconnected, giving up",
                        e
                    );
                    return Err(e);
                }
                log::trace!("Failed to read clipboard from cm: {}, retrying once", e);
                self.stream = None;
                self.read_clipboard_from_cm_ipc_once(deadline, false, &mut reconnected)
            }
        }
    }
}

// Vega 修改：总截止时间还剩多少毫秒，已经到点返回 0。
#[cfg(windows)]
fn cm_ipc_remaining_ms(deadline: std::time::Instant) -> u64 {
    deadline
        .checked_duration_since(std::time::Instant::now())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(target_os = "android")]
fn run(sp: EmptyExtraFieldService) -> ResultType<()> {
    CLIPBOARD_SERVICE_OK.store(sp.ok(), Ordering::SeqCst);
    while sp.ok() {
        if let Some(msg) = crate::clipboard::get_clipboards_msg(false) {
            sp.send(msg);
        }
        std::thread::sleep(Duration::from_millis(INTERVAL));
    }
    CLIPBOARD_SERVICE_OK.store(false, Ordering::SeqCst);
    Ok(())
}

#[cfg(test)]
#[cfg(target_os = "linux")]
mod tests {
    use super::{decode_utf8_prefix, WAYLAND_CLIPBOARD_SKIP_CHECK_MAX_UTF8_BYTES};

    #[test]
    fn decode_utf8_prefix_keeps_utf8_boundary_when_limited() {
        let mut bytes = vec![b'a'; WAYLAND_CLIPBOARD_SKIP_CHECK_MAX_UTF8_BYTES - 1];
        bytes.extend_from_slice("ا".as_bytes());
        let result = decode_utf8_prefix(&bytes).expect("expected decoded prefix");
        assert_eq!(
            result.len(),
            WAYLAND_CLIPBOARD_SKIP_CHECK_MAX_UTF8_BYTES - 1
        );
        assert!(result.chars().all(|c| c == 'a'));
    }
}
