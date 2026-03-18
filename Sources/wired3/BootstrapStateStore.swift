//
//  BootstrapStateStore.swift
//  wired3
//

import Foundation
import WiredSwift

private struct BootstrapState: Codable {
    var version: Int = 1
    var completedSeeds: Set<String> = []
}

final class BootstrapStateStore {
    private let url: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "wired3.bootstrap-state")
    private var state: BootstrapState

    init(workingDirectoryPath: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.url = URL(fileURLWithPath: workingDirectoryPath)
            .appendingPathComponent(".wired-bootstrap-state.json")
        self.state = BootstrapStateStore.loadState(from: self.url, fileManager: fileManager)
    }

    func isCompleted(_ seed: String) -> Bool {
        queue.sync {
            state.completedSeeds.contains(seed)
        }
    }

    func markCompleted(_ seed: String) {
        queue.sync {
            guard !state.completedSeeds.contains(seed) else { return }
            state.completedSeeds.insert(seed)
            saveState()
        }
    }

    private func saveState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let parentURL = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.warning("Could not persist bootstrap state at \(url.path): \(error.localizedDescription)")
        }
    }

    private static func loadState(from url: URL, fileManager: FileManager) -> BootstrapState {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(BootstrapState.self, from: data) else {
            return BootstrapState()
        }

        return state
    }
}
