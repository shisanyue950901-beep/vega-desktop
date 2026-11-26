// Vega：CI 截图开关。Modified for Vega (AGPL-3.0). 新文件，不含上游代码。
//
// 只有在 GitHub Actions 里（GITHUB_ACTIONS=true 且 CI=true）才读取 VEGA_SHOT_*，
// 普通用户机器上这些开关一律无效。
import 'dart:io';

final bool _vegaInCi = Platform.environment['GITHUB_ACTIONS'] == 'true' &&
    Platform.environment['CI'] == 'true';

String? vegaShotEnv(String key) =>
    _vegaInCi ? Platform.environment[key] : null;
