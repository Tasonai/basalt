// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs a saved script link's command in the background, debounced so typing
/// does not spawn a process per keystroke, and cached by exactly what was
/// typed so a later keystroke never overwrites the screen with a stale
/// answer meant for a different query.
///
/// The behavior here is a background process and a timer, not a
/// calculation, so the command bar tests run a copy of it against small
/// scripts they write instead of checking it as a pure function.
final class CommandBarScriptRunner {
    struct Result: Equatable {
        let text: String
        let metadata: ScriptCommandMetadata?
        let jsonPayload: ScriptCommandJSONPayload?
        let mode: ScriptCommandOutputMode
        let rawOutput: String

        init(text: String,
             metadata: ScriptCommandMetadata? = nil,
             jsonPayload: ScriptCommandJSONPayload? = nil,
             mode: ScriptCommandOutputMode = .compact,
             rawOutput: String? = nil) {
            self.text = text
            self.metadata = metadata
            self.jsonPayload = jsonPayload
            self.mode = mode
            self.rawOutput = rawOutput ?? text
        }
    }

    private struct CachedMetadata {
        let modifiedAt: Date?
        let metadata: ScriptCommandMetadata
    }

    /// How long the query has to sit still before a script actually runs.
    static let debounce: TimeInterval = 0.25

    /// Called on the main thread whenever a result becomes ready, so the
    /// caller can refresh what is on screen.
    var onResult: (() -> Void)?

    private var cache: [String: Result] = [:]
    /// The keys whose process is running right now. Without it, a script
    /// slower than the debounce would be launched again by the next refresh
    /// while the first one is still going, since nothing is cached yet.
    /// Touched only from the main thread, like the cache, so it needs no lock.
    private var inFlight: Set<String> = []
    /// What to do with a run's answer once it lands, keyed like the cache.
    /// It holds one at most: the bar copies one answer and closes once, so
    /// only the last Return on a script row decides what happens.
    private var answerHandlers: [String: (Result) -> Void] = [:]
    private var pendingWorkItem: DispatchWorkItem?
    private var generation = 0
    private let metadataLock = NSLock()
    private var metadataCache: [String: CachedMetadata] = [:]

    /// A result only belongs to the current opening of the bar. Clearing the
    /// session also prevents delayed work from a closed bar from publishing a
    /// stale answer when it opens again.
    func reset() {
        generation &+= 1
        cancelPending()
        cache.removeAll()
        inFlight.removeAll()
        answerHandlers.removeAll()
        metadataLock.withLock { metadataCache.removeAll() }
    }

    /// A query that no longer names a script must not leave its delayed run
    /// behind. Work already executing is bounded by Shell's timeout and its
    /// result is ignored unless this opening still owns it.
    func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    /// The answer for this exact link and argument, if the script already
    /// ran for it.
    func cachedResult(linkID: UUID, argument: String) -> Result? {
        cache[key(linkID, argument)]
    }

    /// Parsed and cached v2 metadata headers (`@raycast.*` / `@vorssaint.*`) for a script link.
    func metadata(for link: CommandBarLink) -> ScriptCommandMetadata? {
        guard link.kind == .script else { return nil }
        let path = (link.destination as NSString).expandingTildeInPath
        return resolveMetadata(atPath: path)
    }

    /// Schedules a debounced run, replacing whatever was pending. Does
    /// nothing when a result is already cached for this exact link and
    /// argument, or when that same run is still going.
    func schedule(link: CommandBarLink, argument: String) {
        guard cachedResult(linkID: link.id, argument: argument) == nil,
              !inFlight.contains(key(link.id, argument)) else { return }
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.execute(link: link, argument: argument) }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: workItem)
    }

    /// Runs at once instead of waiting out the debounce, for the moment
    /// Return is pressed before a result exists yet. `whenAnswered` gets the
    /// result once it lands, also when that same run was already going. It
    /// takes the place of one given for an earlier run, and a Return that
    /// waits for the answer row instead drops that one; it is dropped with
    /// the rest of the session when the bar closes.
    func runNow(link: CommandBarLink, argument: String,
                whenAnswered: ((Result) -> Void)? = nil) {
        guard cachedResult(linkID: link.id, argument: argument) == nil else { return }
        let cacheKey = key(link.id, argument)
        answerHandlers = whenAnswered.map { [cacheKey: $0] } ?? [:]
        guard !inFlight.contains(cacheKey) else { return }
        cancelPending()
        execute(link: link, argument: argument)
    }

    /// Runs a v2 script immediately using explicit multi-argument form values.
    func runWithArguments(link: CommandBarLink, arguments: [String],
                          whenAnswered: ((Result) -> Void)? = nil) {
        let joined = arguments
            .map { value -> String in
                if value.contains(where: \.isWhitespace) {
                    let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
                    return "\"\(escaped)\""
                }
                return value
            }
            .joined(separator: " ")
        runNow(link: link, argument: joined, whenAnswered: whenAnswered)
    }

    /// A run waits out its debounce or is going.
    var isAwaiting: Bool { pendingWorkItem != nil || !inFlight.isEmpty }

    private func execute(link: CommandBarLink, argument: String) {
        pendingWorkItem = nil
        let cacheKey = key(link.id, argument)
        let runGeneration = generation
        let path = (link.destination as NSString).expandingTildeInPath
        inFlight.insert(cacheKey)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let metadata = self?.resolveMetadata(atPath: path)
            let positionalArgs = Self.resolvedArguments(rawArgument: argument, metadata: metadata)
            let hasV2Headers = metadata.map(Self.hasScriptCommandHeaders) ?? false
            let status: Int32
            let output: String
            if hasV2Headers {
                var env = ProcessInfo.processInfo.environment
                for idx in 1...3 {
                    let val = positionalArgs.indices.contains(idx - 1) ? positionalArgs[idx - 1] : ""
                    env["VORSSAINT_ARG_\(idx)"] = val
                }
                let runResult = BoundedProcessRunner.run(
                    path,
                    positionalArgs,
                    timeout: Shell.defaultTimeout,
                    maxOutputBytes: 64 * 1024,
                    environment: env
                )
                status = runResult.status
                output = String(decoding: runResult.output, as: UTF8.self)
            } else {
                (status, output) = Shell.run(path, positionalArgs, maxOutputBytes: 64 * 1024)
            }
            // The hop back happens whatever the script printed: a run that
            // ends with nothing to show still has to stop counting as one in
            // flight, or that key would never be runnable again.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.generation == runGeneration else { return }
                self.inFlight.remove(cacheKey)
                let whenAnswered = self.answerHandlers.removeValue(forKey: cacheKey)
                guard let result = Self.buildResult(status: status,
                                                    output: output,
                                                    metadata: metadata,
                                                    failureText: self.failureText) else { return }
                self.cache[cacheKey] = result
                self.onResult?()
                whenAnswered?(result)
            }
        }
    }

    private func resolveMetadata(atPath path: String) -> ScriptCommandMetadata? {
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        if let cached = metadataLock.withLock({ metadataCache[path] }),
           cached.modifiedAt == modifiedAt {
            return cached.metadata
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        let headData = (try? handle.read(upToCount: 16 * 1024)) ?? Data()
        try? handle.close()
        guard let source = String(data: headData, encoding: .utf8) else { return nil }
        let parsed = ScriptCommandHeaderParser.parseMetadata(fromScriptSource: source)
        metadataLock.withLock {
            metadataCache[path] = CachedMetadata(modifiedAt: modifiedAt, metadata: parsed)
        }
        return parsed
    }

    private static func hasScriptCommandHeaders(_ metadata: ScriptCommandMetadata) -> Bool {
        metadata.title != nil
            || metadata.mode != .compact
            || metadata.icon != nil
            || metadata.packageName != nil
            || metadata.description != nil
            || metadata.refreshTime != nil
            || !metadata.arguments.isEmpty
    }

    private static func resolvedArguments(rawArgument: String, metadata: ScriptCommandMetadata?) -> [String] {
        guard let metadata, metadata.arguments.count > 1 else {
            return [rawArgument]
        }
        let tokens = splitArguments(rawArgument)
        let targetCount = min(metadata.arguments.count, 3)
        return (0..<targetCount).map { idx in
            tokens.indices.contains(idx) ? tokens[idx] : ""
        }
    }

    private static func splitArguments(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for ch in raw {
            if escaping {
                current.append(ch)
                escaping = false
                continue
            }
            if ch == "\\" && quote != "'" {
                escaping = true
                continue
            }
            if let q = quote {
                if ch == q {
                    quote = nil
                } else {
                    current.append(ch)
                }
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                continue
            }
            if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func buildResult(status: Int32,
                                    output: String,
                                    metadata: ScriptCommandMetadata?,
                                    failureText: String) -> Result? {
        let mode = metadata?.mode ?? .compact
        let raw = CommandBarLinks.resultText(output)
        if status != 0 {
            let text = raw ?? failureText
            return Result(text: text, metadata: metadata, jsonPayload: nil, mode: mode, rawOutput: text)
        }
        switch mode {
        case .silent:
            return nil
        case .json:
            if let payload = ScriptCommandHeaderParser.parseJSONOutput(output) {
                let copyOrTitle = (payload.copyText?.isEmpty == false ? payload.copyText : nil) ?? payload.title
                return Result(text: copyOrTitle,
                              metadata: metadata,
                              jsonPayload: payload,
                              mode: .json,
                              rawOutput: raw ?? payload.title)
            }
            guard let raw else { return nil }
            return Result(text: raw, metadata: metadata, jsonPayload: nil, mode: .json, rawOutput: raw)
        case .inline:
            guard let raw else { return nil }
            let firstLine = raw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { !$0.isEmpty }) ?? raw
            return Result(text: firstLine, metadata: metadata, jsonPayload: nil, mode: .inline, rawOutput: raw)
        case .compact, .fullOutput:
            guard let raw else { return nil }
            return Result(text: raw, metadata: metadata, jsonPayload: nil, mode: mode, rawOutput: raw)
        }
    }

    private var failureText: String {
        FeatureStrings.commandBar(L10n.shared.language).scriptRunFailed
    }

    private func key(_ linkID: UUID, _ argument: String) -> String {
        "\(linkID.uuidString)|\(argument)"
    }
}
