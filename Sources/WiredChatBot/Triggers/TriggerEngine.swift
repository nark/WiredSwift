// WiredChatBot — TriggerEngine.swift
// Regex-based trigger matching with per-user cooldowns.

import Foundation

// MARK: - Match results

public struct TriggerMatch {
    public let trigger:   TriggerConfig
    public let input:     String
    public let nick:      String
    public let chatID:    UInt32
    public let isPrivate: Bool
}

/// Result returned when a board-post trigger fires.
public struct BoardPostTriggerMatch {
    public let trigger:  TriggerConfig
    public let subject:  String   // thread subject
    public let text:     String   // body of the new post
    public let nick:     String   // author
    public let board:    String   // board path
}

// MARK: - Engine

public final class TriggerEngine {
    private let triggers: [TriggerConfig]

    // Per-trigger-per-user cooldown: "triggerName|nick" -> last fired date
    private var cooldowns: [String: Date] = [:]
    private let lock = NSLock()

    public init(triggers: [TriggerConfig]) {
        self.triggers = triggers
    }

    /// Returns the first matching trigger for the given input, or nil.
    public func match(input: String, nick: String, chatID: UInt32, isPrivate: Bool) -> TriggerMatch? {
        for trigger in triggers {
            // 1. Event type filter
            let types = trigger.eventTypes
            if !types.contains("all") {
                if isPrivate  && !types.contains("private") { continue }
                if !isPrivate && !types.contains("chat")    { continue }
            }

            // 2. Cooldown check
            if trigger.cooldownSeconds > 0 {
                let key = "\(trigger.name)|\(nick)"
                lock.lock()
                let last = cooldowns[key]
                lock.unlock()
                if let last = last, Date().timeIntervalSince(last) < trigger.cooldownSeconds {
                    continue
                }
            }

            // 3. Regex match
            let options: NSRegularExpression.Options = trigger.caseSensitive ? [] : .caseInsensitive
            guard let regex = try? NSRegularExpression(pattern: trigger.pattern, options: options) else {
                continue
            }
            let range = NSRange(input.startIndex..., in: input)
            guard regex.firstMatch(in: input, range: range) != nil else { continue }

            // 4. Record cooldown
            if trigger.cooldownSeconds > 0 {
                let key = "\(trigger.name)|\(nick)"
                lock.lock()
                cooldowns[key] = Date()
                lock.unlock()
            }

            return TriggerMatch(trigger: trigger, input: input, nick: nick,
                                chatID: chatID, isPrivate: isPrivate)
        }
        return nil
    }

    /// Returns the first trigger whose `eventTypes` contains `"board_post"` (or `"all"`)
    /// and whose pattern matches `subject + " " + text`.
    ///
    /// Available template variables in `response`: {nick}, {subject}, {board}, {text}
    public func matchBoardPost(subject: String, text: String,
                               nick: String, board: String) -> BoardPostTriggerMatch? {
        let combined = "\(subject) \(text)"
        for trigger in triggers {
            let types = trigger.eventTypes
            guard types.contains("board_post") || types.contains("all") else { continue }

            // Cooldown — keyed globally per trigger (board events have no per-user key)
            if trigger.cooldownSeconds > 0 {
                let key = "\(trigger.name)|board"
                lock.lock()
                let last = cooldowns[key]
                lock.unlock()
                if let last, Date().timeIntervalSince(last) < trigger.cooldownSeconds { continue }
            }

            let options: NSRegularExpression.Options = trigger.caseSensitive ? [] : .caseInsensitive
            guard let regex = try? NSRegularExpression(pattern: trigger.pattern, options: options)
            else { continue }
            let range = NSRange(combined.startIndex..., in: combined)
            guard regex.firstMatch(in: combined, range: range) != nil else { continue }

            if trigger.cooldownSeconds > 0 {
                let key = "\(trigger.name)|board"
                lock.lock()
                cooldowns[key] = Date()
                lock.unlock()
            }

            return BoardPostTriggerMatch(trigger: trigger, subject: subject,
                                        text: text, nick: nick, board: board)
        }
        return nil
    }

    /// Replaces {key} placeholders in `template` with `variables`.
    public func format(_ template: String, with variables: [String: String]) -> String {
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
