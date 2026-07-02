import Foundation
import SwiftUI

/// Queue of variant-generation jobs, limited concurrency, per-variant status.
@MainActor
final class GenerationCenter: ObservableObject {
    static let shared = GenerationCenter()

    struct JobKey: Hashable {
        let setID: String
        let variant: WallpaperVariant
    }

    enum JobState: Equatable {
        case queued
        case running
        case failed(String)
    }

    private struct SetContext {
        let folderURL: URL
        let originalURL: URL
        let targetSize: CGSize
        let providerID: String
        /// Read once per batch — every Keychain read may prompt the user.
        let apiKey: String?
        let upscalerID: String
        let upscalerKey: String?
    }

    @Published private(set) var states: [JobKey: JobState] = [:]

    private var queue: [JobKey] = []
    private var contexts: [String: SetContext] = [:]
    private var overrides: [JobKey: String] = [:]
    private var runningTasks: [JobKey: Task<Void, Never>] = [:]
    private let maxConcurrent = 2

    private init() {}

    // MARK: - Public API

    func enqueue(set: WallpaperSet, variants: [WallpaperVariant], extraPrompt: String? = nil) {
        guard let originalURL = set.originalURL else { return }
        let providerID = set.meta.providerID ?? ProviderRegistry.defaultProviderID
        let upscalerID = UpscalerRegistry.currentID
        let upscalerNeedsKey = UpscalerRegistry.provider(id: upscalerID)?.requiresAPIKey == true
        contexts[set.id] = SetContext(
            folderURL: set.folderURL,
            originalURL: originalURL,
            targetSize: set.meta.device?.pixelSize ?? CGSize(width: 1024, height: 1024),
            providerID: providerID,
            apiKey: KeychainStore.apiKey(for: providerID),
            upscalerID: upscalerID,
            upscalerKey: upscalerNeedsKey ? KeychainStore.apiKey(for: upscalerID) : nil
        )
        for variant in variants {
            let key = JobKey(setID: set.id, variant: variant)
            if let extraPrompt, !extraPrompt.isEmpty {
                overrides[key] = extraPrompt
            }
            switch states[key] {
            case .queued, .running:
                continue
            default:
                states[key] = .queued
                queue.append(key)
            }
        }
        pump()
    }

    func cancelAll(setID: String) {
        queue.removeAll { $0.setID == setID }
        for (key, state) in states where key.setID == setID {
            if state == .queued { states[key] = nil }
        }
        for (key, task) in runningTasks where key.setID == setID {
            task.cancel()
        }
    }

    func state(setID: String, variant: WallpaperVariant) -> JobState? {
        states[JobKey(setID: setID, variant: variant)]
    }

    func isActive(setID: String) -> Bool {
        states.contains { $0.key.setID == setID && ($0.value == .queued || $0.value == .running) }
    }

    func activeCount(setID: String) -> Int {
        states.filter { $0.key.setID == setID && ($0.value == .queued || $0.value == .running) }.count
    }

    func failedVariants(setID: String) -> [WallpaperVariant] {
        states.compactMap { key, state in
            if key.setID == setID, case .failed = state { return key.variant }
            return nil
        }
    }

    func clearFailures(setID: String) {
        for (key, state) in states where key.setID == setID {
            if case .failed = state { states[key] = nil }
        }
    }

    // MARK: - Scheduling

    private func pump() {
        while runningTasks.count < maxConcurrent, !queue.isEmpty {
            let key = queue.removeFirst()
            guard states[key] == .queued, let context = contexts[key.setID] else { continue }
            states[key] = .running
            let extra = overrides[key]
            runningTasks[key] = Task { [weak self] in
                var failure: Error?
                do {
                    try await Self.perform(key: key, context: context, extraPrompt: extra)
                } catch {
                    failure = error
                }
                self?.finish(key, error: failure)
            }
        }
    }

    private func finish(_ key: JobKey, error: Error?) {
        runningTasks[key] = nil
        overrides[key] = nil
        if let error {
            if error is CancellationError {
                states[key] = nil
            } else {
                states[key] = .failed(error.localizedDescription)
            }
        } else {
            states[key] = nil
        }
        WallpaperStore.shared.refresh()
        pump()
    }

    private nonisolated static func perform(key: JobKey, context: SetContext, extraPrompt: String?) async throws {
        guard let provider = ProviderRegistry.provider(id: context.providerID) else {
            throw ProviderError(message: String(localized: "Unknown image provider."))
        }
        guard let apiKey = context.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingKey(providerName: provider.displayName)
        }

        try await WallpaperFileSystem.ensureDownloaded(context.originalURL)
        let original = try Data(contentsOf: context.originalURL)
        try Task.checkCancellation()

        let prompt = PromptBuilder.editPrompt(for: key.variant, extraInstructions: extraPrompt)
        var image = try await provider.edit(
            image: original,
            prompt: prompt,
            targetSize: context.targetSize,
            apiKey: apiKey
        )
        try Task.checkCancellation()

        // Optional AI upscale pass; a failure here falls back to the native
        // Lanczos fit rather than failing the whole job.
        if ImageUtil.upscaleEnabled,
           let upscaler = UpscalerRegistry.provider(id: context.upscalerID),
           upscaler.requiresAPIKey {
            do {
                image = try await upscaler.upscale(image, to: context.targetSize, apiKey: context.upscalerKey)
            } catch {
                WallpaperResolver.logger.error("AI upscale failed, using native fit: \(error.localizedDescription, privacy: .public)")
            }
            try Task.checkCancellation()
        }

        // Fit exactly to the device resolution and re-encode for storage (HEIC
        // by default), then drop any previous file of this variant in another format.
        let optimized = ImageUtil.processForStorage(image, targetSize: context.targetSize)
        for ext in WallpaperSet.imageExtensions where ext != optimized.fileExtension {
            try? FileManager.default.removeItem(
                at: context.folderURL.appendingPathComponent("\(key.variant.baseName).\(ext)")
            )
        }
        let destination = context.folderURL.appendingPathComponent("\(key.variant.baseName).\(optimized.fileExtension)")
        try WallpaperFileSystem.writeImage(optimized.data, to: destination)
    }
}
