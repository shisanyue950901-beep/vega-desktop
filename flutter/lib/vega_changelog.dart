// Vega 新增文件（AGPL-3.0，基于 RustDesk 1.5.3 修改版）：内置更新日志。
// 每次发版在最前面加一条，和服务器 latest.json 的 notes 保持一致。

class VegaRelease {
  final String version;
  final String date; // ISO 8601（UTC）
  final List<String> items;
  const VegaRelease(this.version, this.date, this.items);
}

const List<VegaRelease> vegaChangelog = [
  VegaRelease('0.7.4', '2026-11-27', [
    '被远程控制时也能在锁定提示卡里检查更新；安装需断开远程后进行',
  ]),
  VegaRelease('0.7.3', '2026-11-26', [
    '被远程控制时，设置页的黑色遮罩换成锁定提示卡，说明为何锁定以及如何开放远程修改',
  ]),
  VegaRelease('0.7.2', '2026-11-26', [
    '远程窗口顶部的控制中心不用时自动隐藏：鼠标离开 2.5 秒后缩成一条细线，移上去就出现',
    '控制中心面板右上角新增图钉，点一下可固定常显，设置会记住',
    '画质三档：流畅 / 均衡 / 原生 4K；走中继时显示「4K · 中继受限」',
    '设置 → 关于 新增「更新日志」，在线更新时显示本次更新内容',
    '移除一个仅供测试截图用的内部开关',
  ]),
  VegaRelease('0.7.1', '2026-11-26', [
    '远程控制窗口新增「远程开机」（经同一局域网内在线的 Vega 电脑代发网络唤醒）',
    '首次支持应用内在线更新（签名校验）',
  ]),
  VegaRelease('0.7.0', '2026-11-25', [
    '全新 Vega 界面：我的设备 / 远程协助 / 设置',
    '单个 exe 即安装器，覆盖安装保留设备 ID',
    'iOS 风格的毛玻璃控制中心与被控端连接小窗',
    '文件传输改为左右双栏，底部显示进度',
    '剪贴板同步更稳定（重试与超时）',
  ]),
];

/// 某个版本的更新要点，找不到返回空列表。
List<String> vegaChangelogFor(String version) {
  for (final r in vegaChangelog) {
    if (r.version == version) return r.items;
  }
  return const [];
}
