# Mac App Store 上架检查

检查日期：2026-09-24。对象：GitHub v0.2.0，提交 `50901a5593417dca6b45839fa098d45a26d9b086`，实际发布的 CoPing.app 0.2.0 (18)。

**结论：NOT READY，当前包不能直接提交。** 这不是 Apple 的拒审结果；这是基于当前代码、实际安装包和当天官方要求的发布前检查。没有上传 App Store Connect，没有修改证书、用户配置或应用行为。

## 已确认的缺口

| 项目 | 当前证据 | 上架前所需结果 |
| --- | --- | --- |
| App Sandbox | 对实际包运行 `codesign -dvvv --entitlements :-`：Signature=adhoc、TeamIdentifier 未设置，无 app-sandbox entitlement。仓库未发现 entitlements 文件 | 建立沙箱商店构建，验证网络、文件与 IPC 权限；hardened runtime 不等于沙箱 |
| 应用自行提供更新 | `UpdateModel.swift:31` 查询 GitHub 最新版，`:55` 下载；`VersionSettingsView` 提供操作入口 | 商店构建排除 GitHub 更新检查、下载链路及 UI；改由商店更新。GitHub 发行版可以保留。普通源码/支持链接不等于更新机制 |
| 包外安装代码 | `HelperInstaller.swift:31` 将包内 Helper 复制到 `~/Library/Application Support/CoPing/bin` 并保留旧副本；`HookTrustLauncher.swift:26` 在支持目录生成可执行 `.command` 并打开终端 | 重做自包含的集成与授权方案，验证无包外代码安装。不能仅把路径移进容器就宣称合规 |
| 登录启动未先取得应用内选择 | `AppModel.swift:131` 默认 true，`:155` 首次启动直接 `setLaunchAtLogin(true)`；最终调用 `SMAppService.mainApp.register()` | 首次默认关闭，由用户明确开启后注册；系统可能显示的后台项目通知不应被当作已获得同意 |
| 提交签名和打包 | 当前只有 ad-hoc GitHub 包及 Developer ID 公证脚本，没有可验证的商店导出包、团队签名和 provisioning 流程 | 使用适用的 App Store 分发签名和配置，完成 Xcode/Transporter 验证。Developer ID 公证是站外分发流程，不能代替商店签名 |
| 隐私政策入口 | README 有简短隐私说明，应用内未发现可访问的隐私政策链接 | 发布完整政策并在应用内和 App Store Connect 提供入口；说明任务标题/项目名、Bark/ntfy、目标标识、保留与删除及联系方法 |
| 隐私清单 | 源码和实际包均无 `PrivacyInfo.xcprivacy`；主应用使用 UserDefaults，Helper 使用 `systemUptime`，监控使用 `lstat` | 按实际用途审核 Required Reason API 类别和理由，打入最终包并验证；不能只写“没有服务器”或盲填理由码 |

规则依据：[App Review Guidelines 2.4.5、5.1.1](https://developer.apple.com/app-store/review/guidelines/)、[证书类型](https://developer.apple.com/help/account/certificates/certificates-overview)、[Required Reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)、[systemUptime 的隐私声明要求](https://developer.apple.com/documentation/foundation/processinfo/systemuptime)。

## 需验证的架构风险

- **外部文件访问和持久授权**：直接修改所选 Codex Home 的 `hooks.json`、读取 `state_*.sqlite`、访问其 IPC socket。`AppModel.swift:212` 的选择器只保存路径，没有 security-scoped bookmark。当前无沙箱成功不能证明沙箱下重启后仍有效；文件选择也不自动证明跨进程 socket 可用。需要在实际沙箱签名包中验证整个连接、重启、升级和权限撤销流程。参见 [App Sandbox 文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)。
- **跨进程集成**：当前终端审核会运行另一 App 内的 Codex 可执行文件，Helper 由 Codex 启动并通过 Unix socket 通知主应用。这一架构在商店包内如何保持自包含、权限一致、用户可理解，尚未证明。不能把终端脚本当作绕过沙箱的方案。
- **Codex 内部接口依赖**：审批状态使用本地 IPC 协议 11，标题读取 Codex SQLite。它们不是 Apple 私有 API，不能仅因此判为违反 Apple 公共 API 条款；但其宿主兼容性、服务条款/授权和审核说明仍需核实。
- **可审核性与功能准确性**：需要给审核员完整的 Codex 与手机通知测试步骤、必要测试资源，准确说明第三方依赖。完成提醒仍来自 Stop 候选，存在提前提醒边界；人工审批实机用例和异步回答取消契约仍有缺口。不得在商店页面声称已可靠识别所有任务终态。
- **商店后台材料**：开发者账号/协议、Bundle ID 所有权、App Store Connect 记录、隐私标签、年龄分级、出口合规、支持网址及截图未访问，全部待核对，不能写成通过。IPv6-only 网络和完整沙箱实机流程也未验证。

## 本次确认没有增加的负担

- 当前产品只通知，不远程控制；无需为了商店引入手机回复、执行或审批。
- 生产通知地址要求 HTTPS；源码未声明第三方 Swift 包依赖。两者不等于完整隐私/供应链认证。
- Apple Silicon、macOS 14 起的支持范围本身不是此次确认的阻碍；需要让商店元数据与实际支持一致。

## 最小决策建议

保留已发布的 GitHub 0.2.0。下一步优先做**沙箱下 Codex 接入的可行性验证**：证明 Helper 如何留在包内、外部 Home 如何由用户授权、进程间通信和重启恢复是否可行，再决定商店版功能范围。通过后才值得完成商店构建分流、隐私材料、签名和截图。若核心接入不能在规则内实现，应调整商店版范围或继续站外分发，不能保证“删更新就能过审”。

## 实际执行的检查

- `rg` 检查源码、包资源、配置和隐私入口；逐项阅读安装器、审核启动器、更新、路径、标题读取和登录项代码。
- `codesign -dvvv --entitlements :- dist/CoPing.app`：实际包 ad-hoc、无 Team ID/沙箱 entitlement。
- `plutil -p dist/CoPing.app/Contents/Info.plist`：0.2.0 (18)，macOS 14。
- 发布前 `script/test.sh`、Helper 五项边界测试、包签名、DMG 校验及 ZIP 解包签名均 PASS；这些是 GitHub 发布验证，不是 App Store 验证。
- 在线读取 Apple 官方规则与文档。未执行 App Store 上传或验证，未试图绕过本机 Xcode 许可。
