# CoPing 兼容性修改验证报告

日期：2026-09-24。

> 以下主体保留首次开发阶段的证据快照（其中“未发布”“未实机验证”等描述仅指该阶段）。0.2.0 发布前新增的真实验证与仍存缺口，以 [0.2.0 发布验证](release-0.2.0.md) 为准。

**整体 PARTIAL；不能据此发布完整兼容认证。**

已实施代码、测试、迁移说明及中英文文案。纯逻辑与本地集成自测 PASS；CP-03 可靠终态、真实桌面 Hook/审批协议、实际签名安装包升级及手机收件没有取得验收证据。本次没有推送、合并、发布、启动用户 CoPing、改用户 Codex 配置/信任或发送真实手机通知。

## CP-00：现场与基线

| 项目 | 本次读取结果 |
| --- | --- |
| 仓库基线 / HEAD | `b1c38b7d544fcd59735d01ddee1fefec75949f54`，与交接文档一致 |
| 初始工作区 | main，干净；无用户改动需要搬移或覆盖 |
| 工作分支 | `compatibility/cp-00-06`；代码未提交，未推送 |
| 规范 | 本次用户提供的 AGENTS.md；仓库内未发现额外 AGENTS.md |
| 系统 | macOS 27.0，build 26A428，arm64 |
| Xcode | 27.0 / 27A266a；默认工具链被未接受许可阻塞，没有代用户接受许可 |
| 可执行构建环境 | CLT Swift 6.4，swiftlang-6.4.0.34.1；进程级选择 macOS 26.5 SDK（25F70） |
| 已安装宿主 | `/Applications/ChatGPT.app`，bundle ID `com.openai.codex`，26.917.71314 / 10954 |
| 该包内引擎 | 对该包内 `Contents/Resources/codex --version` 实际执行：`codex-cli 0.155.0-alpha.16.4`；不是 PATH 中的另一 CLI |
| 活动进程与有效 Home | 未确认；读取进程名被沙箱阻止，没有读取真实配置内容来推断。GUI 的有效 Home 仍需专用任务验证 |
| 状态消息版本 | **未观察到真实消息**。源码仍只接受 11；不能推导当前桌面已经不是 11 |
| 外部数据使用 | 只读取官方 Hooks 文档及固定 tag 的公开源码；没有保存真实 Hook、状态帧、对话或凭据 |

交接文档 F01–F12 与基线源码吻合。F03 的碰撞是确定的源码缺陷，本次合成测试证实修复；不是声称在用户旧任务上复现。F05 的 Stop 终态假设仍未解决。参考 tag 与安装引擎并不相同，不能由静态契约声称当前宿主实机通过。默认旧提问的 Pre/Post 取消闭环已按复审修正，实机支持仍待验；async 仍默认关闭。

## 实际修改与 CP 状态

| 工作包 | 状态 | 实际交付 / 限制 |
| --- | --- | --- |
| CP-00 | PASS（静态/构建环境）；现场事件 PARTIAL | 完整读取交接文档，确认干净基线、独立分支、宿主包及内置引擎；有效 Home/真实消息未确认 |
| CP-01 | PASS（合成与本地 Socket） | 可选 callID/phase/questionMode/sourceID；有边界的编码键；旧 Helper 弱身份稳定 wire ID；IPC 1 和历史 raw value 不变。未编造 root/subagent 身份 |
| CP-02 | PARTIAL | 调用级协调器、阶段去重、有界墓碑、异步候选、accepted 后一次提醒、结构化 answers 结束等待、发送前 take 复核；扩展订阅默认关闭，真实目标宿主尚未验证 |
| CP-03 | BLOCKED（可靠终态/中断） | Stop 记录为 stopCandidate，仍沿用旧完成推送且明确标注限制；停止按轮清除未解决问题/审批。不屏蔽 stop_hook_active，不用延迟推断完成。Interrupt/SessionEnd/子代理清理未接入 |
| CP-04 | PARTIAL | 保留 v11 限制；关键字段错误拒绝、解码事务回退、过滤已结束历史 turn 内容；重连清缓存、读回调代际、初始化截止、退避、自动审查超时兜底、独立诊断；当前桌面精确分类未验证 |
| CP-05 | PARTIAL | 单一来源、显式 App/Home 选择、统一注入、正常审核环境、配置保留/冲突检测、Helper 原子替换与恢复备份、验证指纹、幂等连接。真实签名安装包/组织策略/升级仍待验证 |
| CP-06 | PARTIAL | 中英 UI/README、测试、此报告、迁移回退说明；渲染 UI、实际桌面与手机收件尚未手工验收 |

### 文件清单

- `Sources/CoPingIPC/CodexEvent.swift`、`HookPayloadSanitizer.swift`：可选元数据、强弱身份、调用阶段、白名单响应结构、弱身份退路。未知工具/响应不当完成或已回答。
- `Sources/CoPingCore/Models/CodexQuestionCoordinator.swift`：新建纯状态机；最多 200 个 pending、candidate、terminal key。async candidate 超过 60 秒在后续事件到来时清理；不会由候选定时推送。墓碑为有界缓存，不承诺无限历史重放检测。
- `Sources/CoPing/Stores/AppModel.swift`：独立问题计时、暂停/断开取消、App 监控代际、来源过滤、未确认来源不查询标题；保留审批三档和原有多通道投递。Stop 不清理问题，也没有被提升为可靠终态。
- `Sources/CoPingCore/Services/CodexApprovalStateDecoder.swift`、`CodexApprovalStateMonitor.swift`、`Models/CodexApprovalNotificationCoordinator.swift`：严格 v11 解码、连接与降级、30 秒自动审查无终态后转 unknown，再走原 5 秒兜底；超时不是人工等待证据。连接初始化 5 秒、connect 最多 500ms，重试退避 1–30 秒，近期会话最多 100 个。
- `Sources/CoPingCore/Models/CodexConnectionSource.swift`、`Services/HookConfigurationManager.swift`、`Sources/CoPing/Services/CodexDetector.swift`、`HookTrustLauncher.swift`：统一来源，常见安装路径按 bundle ID 验证，显式选择；默认安装旧提问 Pre/Post 配对，async 仍需显式核验选择。当前没有自动引擎能力探测，未知旧宿主支持该默认契约仍待验。
- Helper 安装器从 `Sources/CoPing/Services/HelperInstaller.swift` 移到 `Sources/CoPingCore/Services/HelperInstaller.swift`，以便测试真实文件替换与模拟签名失败；保留生产代码的 codesign 验证，不改变发布签名策略。
- `Sources/CoPingHook/main.swift`、`Sources/CoPingIPC/UnixSocketTransport.swift`：输入 1 MiB/400ms 上限、本地接收 500ms 超时、仅本地转交；日志中的 session/turn 改为 private。不新增网络或控制输出。
- `Sources/CoPing/Views/CodexSettingsView.swift`、`Sources/CoPingCore/Support/AppLocalization.swift`：来源、观察到的事件/状态版本/时间、扩展契约核验选项与限制说明；问题采用“待查看”。
- `Tests/CoPingCoreTests/main.swift`、`script/test_hook_input.py`：新回归；原有历史、偏好、多 Bark + ntfy、部分失败测试继续执行。
- `README.md`、`README.en.md`、`docs/upgrade-and-rollback.md`、本报告及脱敏测试摘要。

## 已执行命令与结果

```sh
bash script/test.sh
# 默认 Xcode：退出 69，许可未接受；ReleaseVersionTests PASS，构建未执行成功。

DEVELOPER_DIR=/Library/Developer/CommandLineTools bash script/test.sh
# macOS 27 SDK：缺 SwiftUIMacros，构建失败；不是代码回归通过。

# 使用 git archive HEAD 导出到独立临时目录，得到未修改基线：
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
bash /tmp/coping-baseline-isolated/script/test.sh
# ReleaseVersionTests PASS；CoPingSelfTests PASS。

# 修改后完整验证；测试需要本地 Socket 和 NSFileCoordinator 的系统服务权限：
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
bash script/test.sh
# 全部产品构建（包含 warnings-as-errors）、ReleaseVersionTests、CoPingSelfTests PASS。

python3 script/test_hook_input.py .build/out/Products/Debug/CoPingHook
# 5 个输入边界用例 PASS；保持 stdin 打开时约 0.45 秒退出。

git diff --check
# PASS，无空白错误。
```

期间还单独尝试 `swift run --disable-sandbox CoPingSelfTests`：未设缓存路径的尝试被沙箱缓存权限阻塞；设置缓存后，NSFileCoordinator 的系统服务在受限沙箱下返回 Cocoa 512。随后在获准的本地测试权限下运行完整脚本，临时目录迁移测试通过。没有为此修改真实 Codex 配置。

修复过程中出现过 App 编译错误及旧文案/Socket 断言失败，均已修正后重跑。最后成功日志摘要见 [test-results-2026-09-24.txt](test-results-2026-09-24.txt)。CLT 链接器仍提示开发者 Frameworks 搜索路径与 arclite 缺失；没有 Swift 编译 warning/error，运行自测通过。未构建/签名/验证 DMG。

## 验收编号矩阵

**PASS 仅指“证据”栏写明的层级；同编号的真实桌面用例并未因此 PASS。** PARTIAL 表示已做部分实现或验证；BLOCKED 是未有可信外部契约/环境证据，未用假结果替代。

| ID | 状态 | 证据与限制 |
| --- | --- | --- |
| Q01 | PASS synthetic | 旧 Pre 保留、unknown 文案与协调器入队；旧 wire 解码 |
| Q02 | PASS synthetic | 同 session/turn 两个 call 独立 pending |
| Q03 | PASS synthetic | 同 phase 去重、Pre/Post key 不同、accepted 重放抑制 |
| Q04 | PASS synthetic | 一次调用只一个 key；清洗输出不含注入的整组问题正文 |
| Q05–Q07 | PASS synthetic | resolved 取消指定 call，B 保留，乱序墓碑，200 项边界 |
| Q08–Q09 | PASS synthetic | async Pre 不安排提醒，accepted 安排；Stop 不取消 |
| Q10–Q11 | PASS synthetic | 自由文本拒绝；弱身份不合并、未知 turn 不跨调用取消 |
| Q12 | PARTIAL | 名称不推断阻塞；真实 Plan/Default/异步模式未触发验证 |
| Q13 | PARTIAL | 结构化 answers 只叫“等待结束”；任意错误字符串/失败/取消没有可验证关联契约，不能保证取消旧提醒 |
| Q14 | PASS synthetic/helper | 类型/超限/未知工具/敏感文本注入 + 5 个独立 Helper 输入测试 |
| Q15 | PASS production AppModel controlled scheduler；UI PARTIAL | 正式六项回归直接覆盖生产 MainActor 的取消/旧回调/投递资格，使用模拟投递；渲染 UI 与真实推送未验 |
| C01 | PARTIAL | Stop phase 候选及旧投递保留；无根终态证据 |
| C02–C03 | BLOCKED | 其他 Stop Hook 可要求继续；没有验证合并后终态/自动继续链 |
| C04 | BLOCKED | 未给能力未知宿主写入 Interrupt；未接真实中断清理 |
| C05–C06 | PARTIAL | 不监听 SubagentStop，不回放 snapshot 完成；缺 root/subagent 身份与终态关联，不能保证全部场景 |
| C07 | PASS static/synthetic | AgentMessage/FinalAnswer 不是清洗器输入事件；async accepted 只走问题链 |
| C08 | PARTIAL | SessionEnd/未知 Hook 拒绝，不统一发成功；其生命周期清理未实现 |
| A01 | PASS synthetic | 原测试 v11 snapshot/patch；样本不是实机采集 |
| A02–A03 | PASS synthetic | 99 为纯拒绝测试；v11 缺状态/错误 flags 拒绝，不将缺失解释 false |
| A04–A07 | PASS synthetic | 原协调器审查、后续 waiting、无状态兜底、无事件不平白通知；新增无终态审查 watchdog |
| A08 | PARTIAL | 合成混合 snapshot 证实历史审批不重放且当前 waiting 保留；真实重连混合样本未验 |
| A09 | PARTIAL | 本地静默 Socket 初始化超时 PASS；30 秒审查超时逻辑 PASS；内部读回调代际/解码缓存重置已实现，完整重连/迟到回调交错未实测 |
| A10 | PARTIAL | 旧三档偏好/协调器回归 PASS；实际 UI 切换时序待验 |
| M01 | PARTIAL | 自定义 source 路径单测、现有 SQLite 测试 PASS；App 内一致注入静态检查，真实自定义 GUI 宿主/Home 未验 |
| M02–M03 | PASS temporary files | 第三方保留、升级/卸载、幂等、错误 Matcher、相同 Helper 不重装 |
| M04 | PARTIAL | 注入并发编辑检测并保留新文件 PASS；不协调写入在最终比较/rename 间的窗口仍存在，见迁移说明 |
| M05 | PASS local shell | 临时路径含空格、单引号、美元符、反引号，经 printf 严格 round-trip，不执行路径内容 |
| M06 | PASS synthetic；实装 PARTIAL | 新旧 wire、旧事件接收端本地 ID、磁盘 Helper 内容替换通过；真实 signed App/Helper 配套升级待验 |
| M07 | PARTIAL | 模拟签名拒绝保留旧文件、成功替换保留恢复副本 PASS；真实 codesign 拒绝与替换中系统故障未注入 |
| M08 | PARTIAL | 默认写旧提问 PostToolUse 以闭合取消；未知旧宿主对最小契约的支持、真实审核、组织禁用和配置层冲突待验 |
| M09–M10 | PASS existing regression | 旧历史/偏好、多 Bark 与 ntfy、部分成功结果等原自测全部通过；网络是 Mock |
| M11 | PARTIAL | 协调器 reset 及有界墓碑 PASS，App 暂停/断开/来源切换代码接入；实际重启/切换 UI 待验 |
| M12 | PASS static | 手机通道测试不调用 Hook verify；验证指纹只由匹配 source 的事件写入 |
| M13 | PASS synthetic/static；现场 PARTIAL | Hook 正文不落 wire，原网络错误脱敏回归、ID 私有日志；没有新增完整帧日志。真实诊断导出/系统日志未做端到端采集 |
| M14 | PASS local | 错误输入快速无输出退出、本地缺失 Socket 明确失败；不访问真实手机 |

## 契约依据及修正理由

读取日期：2026-09-24。

- [官方 Hooks 文档](https://learn.chatgpt.com/docs/hooks)：Pre/Post 的 tool_use_id、tool_response；Stop 可要求继续，Interrupt 有独立输入契约。外部文档存在一个事件不等于当前桌面实例已支持并触发它。
- [request_user_input_async.rs（rust-v0.156.1）](https://github.com/openai/codex/blob/rust-v0.156.1/codex-rs/core/src/tools/handlers/request_user_input_async.rs)：响应是 JSON 字符串 accepted；消息虽可标 FinalAnswer，依然只是异步问题。清洗器只提取 accepted 的布尔证据，不读取消息正文。
- [request_user_input.rs](https://github.com/openai/codex/blob/rust-v0.156.1/codex-rs/core/src/tools/handlers/request_user_input.rs)：is_blocking 随模式变化，工具结果包含 response.answers。Hook 输入没有足够证据可直接得到该布尔值，因此本实现对旧 Pre 一律 unknown，未从 permission_mode 猜测。
- [registry.rs](https://github.com/openai/codex/blob/rust-v0.156.1/codex-rs/core/src/tools/registry.rs)、[hook_names.rs](https://github.com/openai/codex/blob/rust-v0.156.1/codex-rs/core/src/tools/hook_names.rs)、[tools/mod.rs](https://github.com/openai/codex/blob/rust-v0.156.1/codex-rs/core/src/tools/mod.rs)：默认命名空间保留工具名；matcher 别名不是 payload canonical 名。参考契约支持的仅为这两个精确名称，不添加全工具或问号匹配。

本次保留 IPC 1，通过可选 phase 兼容旧历史。没有编造 Codex 原生 resolved、根任务 final 或协议 12。新 App + 旧 Helper 的 source 未确认是受限状态。PostToolUse 未提供受支持结构时安全忽略，而不是擅自认定用户回答。

## 最少手工验收与阻塞解除条件

1. 在可证明隔离的 Home/测试配置中安装签名 App/Helper，并正常审核 `/hooks`；如果桌面不能隔离，先取得对指定真实配置的授权，不能假装隔离。核实界面路径、build、安装 Helper、审核环境一致。
2. 保持手机通道关闭或使用经授权的专用测试目标，触发普通问题、同轮两次问题、快速回答、异步 accepted 后继续运行。先只保存白名单投影：匿名 session/turn/call、事件名、类型/版本/顺序；不保存原始输入或对话。
3. 在 Plan/Default 分别核对两种问题的 canonical 名、ID、Post 输出及模式。只有真实证据匹配时启用扩展订阅。无法触发工具时记“当前环境不可触发”。
4. 触发人工等待、自动批准、自动审查失败后人工等待、断连/重连，核对真实消息版本和 v11 必需字段。未知版本不删除校验；先取脱敏结构再增加明确适配器。
5. 复现另一 Stop Hook 要求继续、真正结束、中断、子代理结束和恢复历史。必须证明最终只读信号与根任务/执行关联后，才能替换旧 Stop 投递。**CP-03 目前不是已修复状态。**
6. 验证配置/Helper 升级、重新信任、应用重启、暂停/恢复、三档审批切换及中英文设置页布局；确认不补发旧提醒，不串 Home。按迁移文档演练只恢复自有 handler。
7. 最后再经授权测试手机收件。HTTP 请求成功不等于手机显示；本次没有手机端 PASS。

## 六项复审追加验证

六项修复已纳入 `script/test.sh`，修复前逐项实际 FAIL、修复后 PASS，含默认配置、生产 AppModel、可控时钟、模拟监控/推送及真实临时 socket。详细证据、关联边界、迁移变化见 [六项复审报告](regression-six-review.md)。整体 PARTIAL 与既有实机缺口不变。
