# CoPing

CoPing is a native macOS 14+ menu bar app that forwards important Codex desktop events to an iPhone through Bark.

CoPing 是一个原生 macOS 14+ 菜单栏工具，通过 Bark 将 Codex 桌面端的重要事件推送到 iPhone。

## v1 capabilities / 第一版能力

- Task completed / 任务完成
- Permission requested / 权限请求
- User question requested / 普通问题
- Five-second intervention debounce / 介入通知延迟 5 秒确认
- Bark public or self-hosted HTTPS servers / Bark 公共或自建 HTTPS 服务
- CoPing-branded Bark notification icon / 带 CoPing 品牌图标的 Bark 通知
- Automatic English or Simplified Chinese UI based on the system language; all Chinese variants use Simplified Chinese / 根据系统语言自动使用英文或简体中文，所有中文变体统一映射为简体中文
- Device Key stored in macOS Keychain / Device Key 保存于 macOS 钥匙串
- Launch at login / 登录时自动启动

Task failure detection, ntfy, remote approval, and remote replies are intentionally out of scope.

执行失败识别、ntfy、远程审批和远程回答不在第一版范围内。

## Build and run / 构建与运行

```bash
./script/test.sh
./script/build_and_run.sh --verify
```

The Run action in Codex is wired to `./script/build_and_run.sh`.

当前开发机只有 Command Line Tools，因此开发脚本固定使用匹配的 macOS 15.4 SDK。正式分发应安装完整 Xcode。

## First connection / 首次连接

1. Open CoPing settings from the menu bar.
2. Configure an HTTPS Bark server and Device Key, then send a test notification.
3. Choose **Connect Codex**.
4. In the terminal opened by CoPing, enter `/hooks`, review the `CoPingHook` path, and trust all CoPing hooks.
5. Exit the terminal and create a new Codex desktop task. CoPing changes to **Connected** after `SessionStart`.

CoPing merges its handlers into `~/.codex/hooks.json`, preserves existing handlers, creates a timestamped backup, and removes only its own exact command when disconnected.

## Privacy / 隐私

The helper discards prompts, assistant responses, commands, full paths, and tool arguments before sending an event to the app. Local history contains only event type, project basename, timestamp, and delivery result. The Bark Device Key never appears in the request URL or logs.

Helper 会在事件进入 App 前丢弃提示词、回复、命令、完整路径和工具参数。本地记录只包含事件类型、项目名、时间和发送结果。Bark Device Key 不进入 URL 或日志。

## Distribution / 分发

Local development builds use ad-hoc signing with Hardened Runtime:

```bash
./script/build_and_run.sh --build-only
```

For Developer ID signing and notarization:

```bash
COPING_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
COPING_NOTARY_PROFILE="coping-notary" \
./script/package_release.sh
```

The release script requires a complete Xcode installation, a Developer ID Application certificate, and a preconfigured `notarytool` keychain profile.
