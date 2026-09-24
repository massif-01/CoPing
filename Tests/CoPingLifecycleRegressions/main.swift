import Foundation
import CoPingCore

private struct Failure: Error, CustomStringConvertible { let description: String }
private func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw Failure(description: message) }
}
private func question(_ phase: String, call: String? = "call-A", turn: String? = "turn-A", source: String? = "source-A", tool: String = "request_user_input") throws -> CodexEvent {
    var input: [String: Any] = ["hook_event_name": phase, "session_id": "session-A", "tool_name": tool]
    input["tool_use_id"] = call; input["turn_id"] = turn
    if phase == "PostToolUse" { input["tool_response"] = tool.hasSuffix("_async") ? ["accepted": true] : ["answers": [:]] }
    return try HookPayloadSanitizer.sanitize(JSONSerialization.data(withJSONObject: input), sourceID: source)
}
private func permission(_ call: String = "call-A", turn: String? = nil) -> CodexEvent {
    CodexEvent(type: .permissionRequested, sessionID: "session-A", turnID: turn, callID: call, sourceID: "source-A", projectName: "synthetic")
}
private func observation(_ kind: CodexApprovalObservation.Kind, turn: String? = "turn-A", source: CodexApprovalObservation.Source = .live) -> CodexApprovalObservation {
    CodexApprovalObservation(sessionID: "session-A", turnID: turn, source: source, kind: kind)
}
private func count(_ effects: [CodexApprovalCoordinatorEffect]) -> Int {
    effects.filter { if case .notify = $0 { return true }; return false }.count
}
@MainActor private final class Clock {
    var waiters: [(Duration, CheckedContinuation<Void, Never>)] = []
    func sleep(_ delay: Duration) async { await withCheckedContinuation { waiters.append((delay, $0)) } }
    func fire(_ delay: Duration? = nil) {
        let firing = waiters.filter { delay == nil || $0.0 == delay! }
        waiters.removeAll { delay == nil || $0.0 == delay! }
        // Deliberately resumes cancelled tasks too: production must check eligibility.
        firing.forEach { $0.1.resume() }
    }
}
private final class Monitor: CodexApprovalMonitoring {
    var starts = 0, stops = 0
    let health: CodexApprovalStateMonitor.HealthHandler
    let observations: CodexApprovalStateMonitor.ObservationHandler
    init(_ health: @escaping CodexApprovalStateMonitor.HealthHandler, _ observations: @escaping CodexApprovalStateMonitor.ObservationHandler) { self.health = health; self.observations = observations }
    func start() { starts += 1 }; func stop() { stops += 1 }
    func follow(sessionID: String) {}; func unfollow(sessionID: String) {}
}
@MainActor private final class Fixture {
    let directory: URL
    let defaults: UserDefaults
    let suite = "CoPingRegression-\(UUID())"
    let clock = Clock()
    var monitors: [Monitor] = []
    var delivered: [CodexEvent] = []
    var model: AppModel!
    let hooks: HookConfigurationManager
    init(legacyConfiguration: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        let helper = directory.appendingPathComponent("CoPingHook")
        try Data("fixture".utf8).write(to: helper)
        let source = CodexConnectionSource(appPath: directory.appendingPathComponent("Synthetic.app").path, codexHomePath: directory.path, homeOrigin: "synthetic", id: "source-A")
        defaults.set(try JSONEncoder().encode(source), forKey: "codexConnectionSource")
        hooks = HookConfigurationManager(hooksURL: source.hooksURL, helperURL: helper, sourceID: source.id)
        try hooks.installConfiguration()
        if legacyConfiguration {
            var root = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks.hooksURL)) as! [String: Any]
            var groups = root["hooks"] as! [String: Any]
            groups.removeValue(forKey: "PostToolUse"); root["hooks"] = groups
            try JSONSerialization.data(withJSONObject: root).write(to: hooks.hooksURL)
        }
        model = AppModel(startServices: false, defaults: defaults,
            historyStore: DeliveryHistoryStore(fileURL: directory.appendingPathComponent("history")),
            deviceKeyStore: DeviceKeyStore(fileURL: directory.appendingPathComponent("bark")),
            ntfyStore: NtfyConfigurationStore(fileURL: directory.appendingPathComponent("ntfy")),
            helperInstaller: HelperInstaller(destinationURL: helper),
            sleep: { [clock] in await clock.sleep($0) },
            deliveryOverride: { [weak self] in self?.delivered.append($0) },
            monitorFactory: { [weak self] _, health, _, observations in
                let monitor = Monitor(health, observations); self?.monitors.append(monitor); return monitor
            })
    }
    func close() async {
        model.setNotificationsEnabled(false); clock.fire(); await drain(); model = nil
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    func sendHook(_ phase: String, call: String = "call-A") throws {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks.hooksURL)) as! [String: Any]
        let config = root["hooks"] as! [String: Any]
        let groups = config[phase] as? [[String: Any]] ?? []
        guard groups.contains(where: { group in
            guard let pattern = group["matcher"] as? String else { return true }
            return "request_user_input".range(of: pattern, options: .regularExpression) != nil
        }) else { return }
        model.receive(try question(phase, call: call))
    }
}
@MainActor private func drain() async { for _ in 0..<30 { await Task.yield() } }
@MainActor private func r1() async throws {
    let f = try Fixture()
    do {
        try f.sendHook("PreToolUse"); await drain()
        try f.sendHook("PostToolUse")
        f.model.receive(try question("Stop", call: nil)); await drain()
        f.clock.fire(.seconds(5)); await drain()
        try require(!f.delivered.contains { $0.type == .questionRequested }, "default Pre/Post/Stop delivered a resolved question")
        try f.sendHook("PreToolUse", call: "call-B"); await drain()
        f.model.receive(try question("Stop", call: nil)); await drain()
        f.clock.fire(.seconds(5)); await drain()
        try require(f.delivered.contains { $0.callID == "call-B" }, "Stop erased an unresolved independent call")
    } catch { await f.close(); throw error }; await f.close()
    let old = try Fixture(legacyConfiguration: true)
    try old.sendHook("PreToolUse"); await drain()
    let status = old.model.connectionStatus
    await old.close()
    try require(status == .awaitingVerification, "old incomplete subscriptions were marked verified by a Pre hook")
}
@MainActor private func r2() async throws {
    var q = CodexQuestionCoordinator()
    let pre = try question("PreToolUse", turn: nil)
    _ = q.receive(pre); _ = q.receive(try question("PostToolUse", turn: nil))
    try require(q.pendingCount == 0, "same source/session/native call with no turn did not resolve")
    _ = q.receive(try question("PreToolUse", call: "call-B", turn: nil))
    _ = q.receive(try question("PostToolUse", call: "call-B", turn: nil, source: "other-source"))
    _ = q.receive(try question("PostToolUse", call: nil, turn: nil))
    try require(q.pendingCount == 1, "foreign or anonymous termination erased a question")
    var async = CodexQuestionCoordinator()
    _ = async.receive(try question("PreToolUse", tool: "request_user_input_async"))
    _ = async.receive(try question("PostToolUse", tool: "request_user_input_async"))
    try require(async.pendingCount == 1, "accepted was treated as answered")
}
@MainActor private func r3() async throws {
    var c = CodexApprovalNotificationCoordinator()
    let a = permission(), b = permission("call-B")
    _ = c.receive(a); _ = c.receive(b)
    // Explicit native call in the state stream proves which nil-turn hook belongs to turn-A.
    _ = c.receive(observation(.permissionRequested(targetItemID: "call-A", startedAt: a.timestamp)))
    let manual = c.receive(observation(.waitingOnApproval(true)))
    try require(count(manual) == 1, "manual wait did not notify")
    try require(count(c.unknownFallbackFired(key: a.uniqueKey)) == 0, "proven same approval emitted manual plus fallback")
    try require(count(c.unknownFallbackFired(key: b.uniqueKey)) == 1, "nil turn wildcard erased an unrelated call")
    var unproven = CodexApprovalNotificationCoordinator()
    _ = unproven.receive(a)
    _ = unproven.receive(observation(.waitingOnApproval(true), turn: nil))
    try require(count(unproven.unknownFallbackFired(key: a.uniqueKey)) == 1, "unproven nil/nil association suppressed independent fallback")
    var late = CodexApprovalNotificationCoordinator()
    _ = late.receive(a)
    _ = late.receive(observation(.waitingOnApproval(true)))
    _ = late.receive(observation(.permissionRequested(targetItemID: "call-A", startedAt: a.timestamp)))
    try require(count(late.unknownFallbackFired(key: a.uniqueKey)) == 0, "late binding did not cancel the same-stage fallback")
    var reverse = CodexApprovalNotificationCoordinator()
    _ = reverse.receive(a)
    _ = reverse.unknownFallbackFired(key: a.uniqueKey)
    _ = reverse.receive(observation(.permissionRequested(targetItemID: "call-A", startedAt: a.timestamp)))
    try require(count(reverse.receive(observation(.waitingOnApproval(true)))) == 0, "fallback then manual state duplicated the proven same stage")
    _ = reverse.receive(observation(.waitingOnApproval(false)))
    try require(count(reverse.receive(observation(.waitingOnApproval(true)))) == 1, "a new waiting episode was suppressed")
}
@MainActor private func r4() async throws {
    let a = permission(turn: "turn-A")
    var c = CodexApprovalNotificationCoordinator()
    _ = c.receive(a)
    _ = c.receive(observation(.automaticReview(targetItemID: "call-A", status: .inProgress, startedAt: a.timestamp)))
    _ = c.monitorHealthChanged(.unavailable)
    let effects = c.unknownFallbackFired(key: a.uniqueKey)
    try require(effects.contains(.cancelReviewTimeout(key: a.uniqueKey)), "fallback left an orphan review watchdog")
    let f = try Fixture()
    do {
        f.model.setApprovalNotificationMode(.actionNeeded); f.model.receive(a); await drain()
        let old = f.monitors.last!
        old.health(.ready)
        old.observations([observation(.automaticReview(targetItemID: "call-A", status: .inProgress, startedAt: a.timestamp))]); await drain()
        f.clock.fire(.seconds(30)); await drain()
        try require(f.model.approvalStateHealth == .ready, "single-item timeout overwrote connection health")
        f.clock.fire(.seconds(5)); await drain()
        try require(f.delivered.count == 1, "review timeout lost fallback")
        f.model.receive(permission("call-B", turn: "turn-A")); await drain()
        f.model.setNotificationsEnabled(false); f.model.setNotificationsEnabled(true)
        old.health(.unavailable); old.observations([observation(.waitingOnApproval(true))])
        f.clock.fire(); await drain()
        try require(f.delivered.count == 1, "old generation callback delivered after resume")
        let current = f.monitors.last!
        current.health(.ready)
        // Both observations execute in one production callback before the queued delivery.
        current.observations([observation(.waitingOnApproval(true)), observation(.waitingOnApproval(false))])
        await drain()
        try require(f.delivered.count == 1, "ended wait remained eligible at the delivery boundary")
        let b = permission("call-C", turn: "turn-A")
        f.model.receive(b); await drain()
        current.observations([observation(.automaticReview(targetItemID: "call-C", status: .inProgress, startedAt: b.timestamp))]); await drain()
        current.health(.unavailable); await drain()
        f.clock.fire(.seconds(5)); await drain()
        current.health(.ready); await drain()
        f.clock.fire(.seconds(30)); await drain()
        try require(f.model.approvalStateHealth == .ready && f.delivered.count == 2, "orphan review overwrote recovered health or repeated delivery")
    } catch { await f.close(); throw error }; await f.close()
}
@MainActor private func r5() async throws {
    let f = try Fixture()
    do {
        f.model.setApprovalNotificationMode(.actionNeeded)
        // Start through an ordinary hook, just as in production.
        f.model.receive(permission(turn: "turn-A")); await drain()
        f.model.setNotificationsEnabled(false)
        let countBefore = f.monitors.count
        f.model.setNotificationsEnabled(true); await drain()
        try require(f.monitors.count == countBefore + 1, "resume did not restart action-needed monitoring")
        let current = f.monitors.last!
        current.observations([observation(.waitingOnApproval(false), source: .snapshot)]); await drain()
        try require(f.delivered.isEmpty, "historical inactive snapshot notified")
        current.observations([observation(.waitingOnApproval(true), source: .snapshot)]); await drain()
        try require(f.delivered.count == 1, "current unresolved snapshot wait was lost on resume")
        current.observations([observation(.waitingOnApproval(true), source: .snapshot)]); await drain()
        try require(f.delivered.count == 1, "replayed current snapshot duplicated notification")
        f.model.setNotificationsEnabled(false); f.model.setApprovalNotificationMode(.none)
        let stoppedCount = f.monitors.count
        f.model.setNotificationsEnabled(true)
        try require(f.monitors.count == stoppedCount, "ignore mode incorrectly started monitor")
    } catch { await f.close(); throw error }; await f.close()
}
private final class ReceivedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CodexEvent] = []
    func append(_ event: CodexEvent) { lock.lock(); defer { lock.unlock() }; events.append(event) }
    var value: [CodexEvent] { lock.lock(); defer { lock.unlock() }; return events }
}
@MainActor private func r6() async throws {
    let old = CodexEvent(type: .completed, sessionID: "session-A", turnID: "turn-A", projectName: "synthetic", timestamp: Date(timeIntervalSince1970: 123))
    let wire = try JSONEncoder().encode(old)
    let first = try JSONDecoder().decode(CodexEvent.self, from: wire).addingEventIDIfMissing()
    let replay = try JSONDecoder().decode(CodexEvent.self, from: wire).addingEventIDIfMissing()
    try require(first.uniqueKey == replay.uniqueKey, "identical old wire gained new identity on replay")
    let next = CodexEvent(type: .completed, sessionID: "session-A", turnID: "turn-A", projectName: "synthetic", timestamp: old.timestamp.addingTimeInterval(1)).addingEventIDIfMissing()
    try require(first.uniqueKey != next.uniqueKey, "new candidate in same turn was suppressed")
    let new1 = try question("Stop", call: nil), new2 = try question("Stop", call: nil)
    try require(new1.uniqueKey != new2.uniqueKey, "distinct helper invocations were collapsed")
    try require(new1.addingEventIDIfMissing().uniqueKey == new1.uniqueKey, "new wire ID changed at receiver")
    let path = "/tmp/coping-r6-\(UUID()).sock"
    let received = ReceivedEvents(), ready = DispatchSemaphore(value: 0)
    let server = UnixSocketServer(path: path) { received.append($0); ready.signal() }
    try server.start(); defer { server.stop() }
    try UnixSocketClient.send(old, path: path)
    try UnixSocketClient.send(old, path: path)
    try UnixSocketClient.send(next, path: path)
    for _ in 0..<3 { try require(ready.wait(timeout: .now() + 2) == .success, "socket replay timed out") }
    let events = received.value
    try require(events[0].uniqueKey == events[1].uniqueKey && events[0].uniqueKey != events[2].uniqueKey, "default socket normalization changed transport identity")
    let f = try Fixture()
    for event in events { f.model.receive(event) }; await drain()
    let deliveredCount = f.delivered.count
    await f.close()
    try require(deliveredCount == 2, "App completion dedup either replayed or lost a new candidate")
}
@main private struct Regressions {
    @MainActor static func main() async {
        let tests: [(String, () async throws -> Void)] = [("R1", r1), ("R2", r2), ("R3", r3), ("R4", r4), ("R5", r5), ("R6", r6)]
        var failed = 0
        for (id, test) in tests {
            do { try await test(); print("\(id): PASS (production components + non-loss counterexamples)") }
            catch { failed += 1; print("\(id): FAIL: \(error)") }
        }
        exit(failed == 0 ? 0 : 1)
    }
}
