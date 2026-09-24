<p align="center">
  <img src="assets/readme/coping-hero.png" width="100%" alt="CoPing：Codex 做完了，手机会告诉你">
</p>

<p align="center">中文 · <a href="README.en.md">English</a></p>

CoPing 是一个 macOS 菜单栏小工具。让 Codex 在 Mac 上跑着，你去忙别的——任务完成、有问题要回答、或者需要你来审批时，CoPing 会直接推送到手机（支持 Bark 和 ntfy，可以同时开）。

## 会收到哪些通知

- **完成候选提醒**：沿用 Stop 提醒；其他 Hook 要求继续时可能提前通知，可靠终态适配尚未完成。
- **有问题待查看**：按调用提醒；不把未知模式或异步问题说成任务已暂停。
- **等待审批**：可以按自己的习惯选提醒方式。

审批通知可以按需调整，有三档：

| 选项 | 什么时候用 |
| --- | --- |
| **全部提醒** | 每次审批请求都通知我 |
| **仅人工介入** | 只在必须我来操作时通知（推荐） |
| **全部忽略** | 不想收审批通知 |

**推荐"仅人工介入"**：Codex 自己能处理的审批不会打扰你，只有它明确在等你操作时才响。CoPing 偶尔没法判断时，宁可多发一条，避免漏掉重要请求。

> 任务完成和提问通知不受这三档影响。
>
> CoPing 只做通知，不提供手机回复、远程执行或远程审批。

## 准备工作

- macOS 14 或更高版本
- Codex 桌面 App
- 手机上装好 [Bark](https://github.com/Finb/Bark) 或 [ntfy](https://ntfy.sh/) —— 两个都是可以从 App Store 免费下载的推送通知 App（二选一或都装）

### 安装 CoPing

去 [GitHub Releases](https://github.com/massif-01/CoPing/releases) 下载最新的 `CoPing-macOS-arm64.dmg`，打开后把 `CoPing.app` 拖进"应用程序"文件夹就好。

**macOS 拦截怎么办？** 如果出现"无法验证开发者"或"App 已损坏"的提示，先确认安装包来自本仓库，然后在终端跑这两行：

```bash
xattr -dr com.apple.quarantine /Applications/CoPing.app
open /Applications/CoPing.app
```

> 只对你信任来源的 App 执行这两行命令。

## 配置手机通知

Bark 和 ntfy 都是 App Store 上的免费 App，用来接收推送通知。可以只用其中一个，也可以同时开——某个通道临时出问题，不影响另一个。

### 配置 Bark

1. 打开 iPhone 上的 Bark，复制完整推送地址或 Device Key。
2. 在 CoPing 里打开“设置 → Bark”，粘贴第一个地址。
3. 如需推送到更多设备，点击“添加更多 Bark 推送地址”，逐个粘贴。
4. 点击“保存并测试全部地址”；所有目标都会独立并发发送，确认手机收到后再启用 Bark。

在 Bark 首页的示例 URL 卡片上，点图中标注的按钮就能复制 Device Key：

<p align="center">
  <img src="assets/readme/copy-bark-device-key.png" width="640" alt="在 Bark 首页复制 Device Key 的按钮位置">
</p>

只填写 Device Key 时会使用上方的默认服务地址。也可以在任意一行粘贴 Bark 官方或自建 HTTPS 服务的完整推送地址；某个地址失败不会阻止其他地址发送。

### 配置 ntfy

ntfy 走官方的 `ntfy.sh`，不用注册账号，也不用自备服务器。

1. 在 CoPing 里打开"设置 → ntfy"，复制那个自动生成的 Topic。
2. 打开手机上的 ntfy，点新增订阅。
3. 把刚才复制的 Topic 粘贴到 **Topic name** 里。

<p align="center">
  <img src="assets/readme/ntfy-add-subscription.jpg" width="560" alt="在 ntfy 新增订阅页面粘贴 Topic">
</p>

4. 回到 CoPing，点"保存并发送测试通知"。
5. 手机收到通知后，打开"启用 NTFY"。

Topic 相当于这条通道的通知密码，不要公开分享。如果重新生成了 Topic，手机上的订阅也要跟着换。

## 连接到 Codex

1. 在 CoPing 里打开"设置 → Codex"，点"连接 Codex"。
2. CoPing 会打开一个终端，看到光标后输入 `/hooks` 回车。
3. 找到列表里的 `CoPingHook`，选"信任全部"。
4. 输入 `/quit`，关闭终端，再用一个无敏感内容的专用任务验证真实 Hook。打开审核终端或手机通道测试成功，都不代表 Codex 的全部事件已验证。

不需要另外装命令行版 Codex。连接前已经开着的旧对话可能不会立刻生效，遇到这种情况新建一个 Codex 任务就好。

## 0.2.0 兼容性更新

- 在“设置 → Codex → 高级设置与诊断”查看宿主、Codex Home、最近 Hook 和审批状态消息版本。可在断开后选择自定义 App/Home；默认 Home 来自应用进程的 `CODEX_HOME`，否则为 `~/.codex`，不假设 Finder 继承 shell 环境。
- 默认对旧提问配对订阅 `PreToolUse`/`PostToolUse`，按原生调用 ID 取消已结束的等待；未知旧宿主对该最小契约的支持仍需隔离验证。新版问题卡片没有提醒时，可在高级设置中开启“新版问题卡片提醒”并重新连接；此选项默认关闭。
- 同轮不同问题独立计时；已知调用结束可以取消尚未发送的提醒。异步 Pre 不直接推送，`accepted: true` 只表示已提出问题；普通 Stop 不取消该提醒。一组问题仅推固定提示，不推问答全文。
- 审批消息仍只适配版本 **11**。未知版本、关键字段异常或状态失联时保守提醒已收到的审批；这不意味着当前桌面的版本已经改变。
- 暂停或断开会取消待发提醒；发往远端服务的请求无法撤回。旧 Helper 事件可继续接收，但不能确认新来源，任务标题也不从未确认的 Home 查询。

本地回归通过；在 ChatGPT.app 26.917.71314 上已观察到状态版本 11，并经用户确认 ntfy 手机收件、重复提问及暂停/恢复的基本流程。根任务可靠终态、Interrupt/子代理身份、真实人工审批及异步回答取消契约仍待验证。详见[兼容性报告](docs/compatibility-verification.md)与[升级及回退](docs/upgrade-and-rollback.md)。

## 隐私说明

- 不需要账号，CoPing 没有自己的中转服务器。
- CoPing 不直接转发问题/回答正文、工具命令或完整文件路径；任务标题可能包含你输入的文字。
- 通知里可能带有任务标题和项目名；这些信息本身也可能敏感。
- "仅人工介入"的判断完全在本地进行，不保存也不上传对话内容。
- 通知发出去时，Bark 或 ntfy 服务会收到最终显示在手机上的那段文字。
- 本地历史只记录通知类型、项目名、时间、推送目标和发送结果，不保存完整推送地址或 Device Key。

妥善保管你的 Bark Device Key 和 ntfy Topic。

## 其他

- Bark 支持多个推送地址并发发送，并可与 ntfy 同时推送
- 查看最近 100 条通知记录，包括各推送目标的发送结果
- 开机自动启动
- 支持简体中文和英文界面
- 应用内直接检查和下载新版本

## 协议

[Apache License 2.0](LICENSE)
