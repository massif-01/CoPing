<p align="center">
  <img src="assets/readme/coping-hero.png" width="100%" alt="CoPing: Codex is done, and your phone lets you know">
</p>

<p align="center"><a href="README.md">中文</a> · English</p>

CoPing is a macOS menu bar app. Let Codex run on your Mac while you go do something else — when a task finishes, needs an answer, or needs your approval, CoPing pushes a notification straight to your phone (supports Bark and ntfy, and you can enable both).

## What you'll be notified about

- **Completion candidate:** The legacy Stop notification remains. It may fire before another Hook requests continuation; reliable terminal detection is not yet implemented.
- **Question to review:** Each call is tracked separately. Unknown and asynchronous questions do not imply the task is paused.
- **Waiting for approval:** Choose how you want to be notified.

Approval notifications have three options:

| Option | When to use |
| --- | --- |
| **All** | Notify me for every approval request |
| **Action Needed** | Only notify me when I must act (recommended) |
| **None** | I don't need approval notifications |

**"Action Needed" is recommended.** Approvals Codex can handle on its own won't bother you — you'll only hear from CoPing when Codex is clearly waiting on you. When CoPing can't tell for certain, it errs on the side of notifying you so nothing slips through.

> Task-complete and question notifications are not affected by this setting.
>
> CoPing is notification-only. It does not provide phone replies, remote execution, or remote approval.

## What you need

- macOS 14 or later
- The Codex desktop app
- [Bark](https://github.com/Finb/Bark) or [ntfy](https://ntfy.sh/) on your phone — both are free apps available on the App Store (pick one or use both)

### Install CoPing

Download the latest `CoPing-macOS-arm64.dmg` from [GitHub Releases](https://github.com/massif-01/CoPing/releases), open it, and drag `CoPing.app` into your Applications folder.

**macOS blocking the app?** If you see "cannot verify the developer" or "app is damaged," first confirm the download came from this repository, then run:

```bash
xattr -dr com.apple.quarantine /Applications/CoPing.app
open /Applications/CoPing.app
```

> Only run these commands for an app from a source you trust.

## Set up phone notifications

Bark and ntfy are free App Store apps for receiving push notifications. You can use just one or enable both — if one channel has a hiccup, the other still delivers.

### Set up Bark

1. Open Bark on your iPhone and copy the complete push URL or Device Key.
2. In CoPing, open Settings → Bark and paste the first address.
3. To notify more devices, click “Add another Bark push URL” and paste each additional address.
4. Click “Save and test all addresses.” CoPing sends to every destination independently and concurrently; once the phones receive the tests, enable Bark.

On Bark's home screen, tap the marked button on the sample URL card to copy your Device Key:

<p align="center">
  <img src="assets/readme/copy-bark-device-key.png" width="640" alt="Where to copy the Device Key on Bark's home screen">
</p>

Entering only a Device Key uses the default server shown above. Any row can instead contain a complete push URL for the official Bark service or a self-hosted HTTPS server. One failed address does not block the others.

### Set up ntfy

ntfy uses the official `ntfy.sh` service — no account, no server, nothing extra to set up.

1. In CoPing, open Settings → ntfy and copy the auto-generated Topic.
2. Open ntfy on your phone and tap Add subscription.
3. Paste the Topic into **Topic name**.

<p align="center">
  <img src="assets/readme/ntfy-add-subscription.jpg" width="560" alt="Paste the Topic on ntfy's Add subscription screen">
</p>

4. Back in CoPing, click "Save and send test notification."
5. Once it arrives on your phone, turn on "Enable NTFY."

Your Topic acts like a password for this notification channel — don't share it publicly. If you generate a new Topic, update the subscription on your phone too.

## Connect Codex

1. In CoPing, open Settings → Codex and click "Connect Codex."
2. CoPing opens a terminal window. At the prompt, type `/hooks` and press Return.
3. Find `CoPingHook` in the list and select "Trust all."
4. Type `/quit`, close the terminal, and verify a real Hook in a dedicated task without sensitive content. Opening review or testing a push channel does not verify every Codex event.

You don't need to install the Codex CLI separately. Conversations that were already open before connecting may not pick up the hooks right away; starting a new Codex task will sort it out.

## 0.2.0 compatibility update

- Settings → Codex → Advanced Settings & Diagnostics shows the host, Codex Home, observed Hooks and approval state-message version. Disconnect before selecting a custom App/Home. The default Home uses the app process's `CODEX_HOME`, otherwise `~/.codex`; Finder is not assumed to inherit your shell environment.
- The default pairs `PreToolUse` and `PostToolUse` for the legacy question tool, resolving waits by native call ID. Unknown older hosts still require isolated validation of this minimum contract. If newer question cards produce no reminder, enable the newer question-card option in advanced settings and reconnect; it is off by default.
- Different calls in one turn keep separate timers. A known call ending cancels its unsent reminder. Async Pre alone does not notify; `accepted: true` means the question was presented, not answered. Ordinary Stop does not cancel it. A group of questions produces one generic reminder without question/answer text.
- Approval decoding still accepts only version **11**. Unknown formats, missing critical fields and unavailable monitoring trigger conservative notifications for received approvals. This is not evidence that the current desktop changed its message version.
- Pause/disconnect cancels pending work. Requests already dispatched to a remote service cannot be recalled. Old Helper events remain receivable but cannot verify a newly selected source; titles are not queried from an unconfirmed Home.

Local builds and synthetic tests are separate from real desktop compatibility. Version 11 was observed on ChatGPT.app 26.917.71314; the user confirmed ntfy phone receipt, repeated questions and basic pause/resume behavior. Reliable root completion, Interrupt/subagent identity, real human approval and the async-answer cancellation contract remain unverified. See the [verification report](docs/compatibility-verification.md) and [upgrade/rollback guide](docs/upgrade-and-rollback.md).

## Privacy

- No account required. CoPing has no relay server of its own.
- CoPing does not directly forward question/answer bodies, tool commands or full file paths; task titles may contain text you entered.
- Notifications may include the task title and project name, which can themselves be sensitive.
- "Action Needed" checks locally whether Codex is waiting for you — no conversation content is saved or uploaded.
- When you use Bark or ntfy, that service receives the final text shown on your phone.
- Local history stores only the notification type, project name, time, destination, and delivery result. Complete push URLs and Device Keys are not stored there.

Keep your Bark Device Key and ntfy Topic private.

## Other features

- Multiple concurrent Bark push URLs, with Bark and ntfy available at the same time
- Delivery history for the latest 100 notifications, per destination
- Launch at login
- Simplified Chinese and English
- Check for and download updates from inside the app

## License

[Apache License 2.0](LICENSE)
