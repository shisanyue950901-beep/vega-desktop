# 被控端中继识别调研（只读）

- 结论：`src/server/connection.rs` 与 `src/server.rs` 中，`Connection` 层没有中继/直连标记，连接一旦进入 `create_tcp_connection`（server.rs:213）就与直连不可区分。
- 只有建连路径知道：`create_relay_connection`（server.rs:369）调用 `create_relay_connection_`（server.rs:398），后者主动向 `relay_server` 拨号（server.rs:408-414），发送 `RequestRelay { uuid }`（server.rs:417-422）。
- 随后同一个 `Stream` 被交给 `create_tcp_connection`（server.rs:423），中继身份没有被继续传递。
- `ConnectionMeta`（server.rs:89-93）只有 `control_permissions` / `controlled_context`；`Connection::start`（connection.rs:532）只解构这两项（connection.rs:540-543），`Connection` 仅保存 `stream`（connection.rs:584）。
- `connection.rs` 全文没有 relay/直连判断（唯一 relay 字样是 connection.rs:96 的注释），因此被控端后续逻辑无法得知当前连接是否走中继。
