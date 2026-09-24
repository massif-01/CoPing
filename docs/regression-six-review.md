# 六项复审修复与验证（2026-09-24）

范围：接续 `compatibility/cp-00-06` 的未提交实现，保留之前修改；HEAD 仍为 b1c38b7。未推送、合并、发布，未修改真实 Codex 配置或信任。

## 复现方法与结果

先增加依赖注入和正式回归入口，再修改六项行为。依赖注入仅将原 AppModel 的存储、监控连接、时钟、投递出口变为可替换参数，生产默认实现不变。修复前六项全部实际失败，输出见 `regression-six-before.txt`，不是从源码推测的预期结果。修复后命令输出见 `regression-six-after.txt`。

入口 `script/test.sh` 现在同时执行原有 CoPingSelfTests 和 `Tests/CoPingLifecycleRegressions/main.swift`。后者直接编译生产 AppModel 与平台适配器、链接生产 Core/IPC，没有复制一套应用逻辑。使用独立 UserDefaults suite、临时 hooks/Helper/历史/Bark/ntfy 文件、模拟状态连接/投递；R6 还使用真实临时 Unix socket。可控时钟故意允许已取消任务的等待返回，以检查生产任务自身是否拒绝迟到回调。生产延迟仍为 5/30 秒。

| 项目 | 修复前实际失败 | 修复 | 修复后与防漏报反例 |
| --- | --- | --- | --- |
| R1 默认取消闭环 | 默认 Pre→已结束→Stop→计时到期，仍投递问题 | 默认旧工具 matcher 同时安装 Pre/Post；仅结构化 answers 结束同一次调用；Stop 不清理 | PASS：读取真实默认配置决定哪些 Hook 到达生产 AppModel；已结束不发，另一未解决调用在 Stop 后仍发；旧配置缺 Post 时，单条 Pre 不会把连接标成已验证 |
| R2 缺 turn 的调用关联 | 同来源/session/call 的结束未取消 pending | 原生 call 是关联身份；key 仍包含 source/session/可选 turn/call，nil 是确切值，不是通配符 | PASS：同作用域无 turn 调用取消；异来源/无 call 结束不清理；async accepted 仍产生待查看提醒 |
| R3 审批阶段关联 | 明确同 call 的状态事实后，人工等待和兜底仍各发一次 | 保留有界 permission fact，通过同 session 的原生 call 绑定缺 turn Hook 与已知 turn；使用有界投递记录统一该等待阶段 | PASS：人工先到、兜底先到、关联事实晚到都不重复；无证据的另一个 nil-turn 调用仍保留兜底；false→true 新等待仍提醒 |
| R4 任务与健康状态 | 兜底移除 pending 却留下审查 watchdog | 所有终结统一清理两种计时器；全局取消显式清空任务；回调核对代次、取消标记、模式、开关、任务资格；单项超时不修改连接健康 | PASS：超时仍有兜底；恢复后旧计时器/监控回调不投递、不污染健康；投递排队期间等待已结束则拒绝发送 |
| R5 暂停恢复 | 恢复通知后监控未重启 | 恢复时按当前模式/连接暂停状态重新启动监控，暂停期间不启动；新监控有新代次 | PASS：不需等待新 Hook，当前 snapshot 等待即可提醒一次；inactive snapshot 不发；忽略模式不启动 |
| R6 传输重放 | 相同旧 wire 每次接收获得随机 ID | 接收端用已有版本/种类/作用域/创建时间等生成稳定 legacy-wire ID；新 Helper 的 UUID 只在一次 Hook 执行时生成 | PASS：实际 socket 相同 wire 重发后 App 只投递一次；同轮新时间候选独立投递；两次新 Helper Stop 各有身份 |

R3 的原始“两个 nil turn 提醒”本身不能证明重复。**无原生 call→已知等待阶段的证据时，保留兜底**，不以 session/nil 清理。测试明确包含这种反例。待发投递资格使用同一协调器记录；等待结束、reset 或明确调用终结会使对应资格失效，不能撤回已经发送到远端的请求。

## 默认配置调整的依据与限制

前次实现把 PostToolUse 整体绑在扩展提问开关后，导致默认旧提问没有取消输入。现将旧 `request_user_input` 的 Pre/Post 配对作为默认通知契约；扩展开关只扩展到 async。参考源码 [rust-v0.156.1 hook_config.rs](https://github.com/openai/codex/blob/rust-v0.156.1/codex-rs/config/src/hook_config.rs) 定义 PostToolUse，`tools/registry.rs` 保留 tool_use_id，旧工具 handler 等待结束后返回 answers；这些证明参考契约，不证明本机运行时已触发。

未通过修改用户 hooks.json 来验收。**未知旧宿主是否接受并触发 PostToolUse、是否有原生 call ID，仍须隔离实测；不支持该最小契约的宿主不能标为取消闭环已兼容。** 不应将此配置直接发布给尚未验证的旧宿主群体。扩展 async 未自动启用。无 call 的旧 Helper 不具备可靠按调用取消能力。新旧版本或字段缺失导致证据不足时，不借 Stop 批量清理来掩盖它。

## 执行命令

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
bash script/test_lifecycle_regressions.sh
# 修复前退出 1：R1–R6 FAIL；修复后退出 0。

DEVELOPER_DIR=/Library/Developer/CommandLineTools \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
bash script/test.sh
# 退出 0：release version、warnings-as-errors 构建、原有自测、新六项回归 PASS。

python3 script/test_hook_input.py .build/out/Products/Debug/CoPingHook
# 退出 0：4 种无效输入 + stdin 截止共 5 项 PASS；没有发送有效事件。

git diff --check
# 退出 0，无输出。
```

本环境需要允许 NSFileCoordinator 系统服务和临时 socket 的隔离测试执行；第一次沙箱内运行 R1/R5 的文件协调失败属于环境失败，随后在相同临时测试范围重跑才取得六项行为失败记录。检查脚本用法时曾误传 `--help` 为 Helper 路径并得到 FileNotFoundError，该次未执行测试；改用实际构建产物后以上 5 项通过。没有接受 Xcode 许可或改全局开发工具路径。CLT 链接器仍有之前的系统目录/arclite 警告。

## 仍未验证

整体仍为 PARTIAL，CP-03 可靠完成/Interrupt/子代理关系仍 BLOCKED。真实桌面状态版本没有观察到，继续限定 11；默认旧提问与 async 的真实事件顺序、签名安装包升级、真实信任审核、暂停恢复实机表现、手机收件均待手工验收。旧 wire 的所有身份字段与创建时间完全相同则无法区分两次新事件；稳定去重不解决上游再次执行 Hook 的身份缺失问题。

迁移：重新连接才更新自有 Post handler，并依正常流程审核；保留第三方配置。App/Helper/订阅一起升级与回退。具体操作见 `upgrade-and-rollback.md`。
