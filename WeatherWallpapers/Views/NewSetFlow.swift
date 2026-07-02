import SwiftUI
import PhotosUI

/// Wizard for a new wallpaper set:
/// 1. name + target device → 2. source image (photos / files / AI) → 3. review & start.
struct NewSetFlow: View {
    @EnvironmentObject private var store: WallpaperStore
    @EnvironmentObject private var center: GenerationCenter
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case setup, image, review
    }

    @State private var step: Step = .setup

    // Step 1
    @State private var name = ""
    @State private var selectedDeviceID: String?
    @State private var showCustomDeviceForm = false
    @State private var customName = ""
    @State private var customWidth = ""
    @State private var customHeight = ""

    // Step 2
    @State private var originalData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var generationPrompt = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    /// Billed source-image generations (every attempt, kept or not) — written
    /// to the set's ledger once the folder exists.
    @State private var pendingUsage: [UsageRecord] = []

    // Step 3
    @State private var providerID = ProviderRegistry.defaultProviderID
    @State private var templateID = PromptTemplate.defaultID
    @State private var creationError: String?

    private var selectedDevice: DeviceSpec? {
        store.allDevices.first { $0.id == selectedDeviceID }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .setup: setupStep
                case .image: imageStep
                case .review: reviewStep
                }
            }
            .navigationTitle("New Wallpaper Set")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                navigationBar
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    // MARK: - Step 1: name + device

    private var setupStep: some View {
        Form {
            Section("Name") {
                TextField("My Wallpaper", text: $name)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
            }
            Section {
                Picker("Device", selection: $selectedDeviceID) {
                    Text("Choose a device…").tag(String?.none)
                    ForEach(DeviceSpec.Category.allCases) { category in
                        let devices = store.allDevices.filter { $0.category == category }
                        if !devices.isEmpty {
                            Section(category.localizedName) {
                                ForEach(devices) { device in
                                    Text("\(device.name) — \(device.resolutionText)")
                                        .tag(String?.some(device.id))
                                }
                            }
                        }
                    }
                }
                Button {
                    showCustomDeviceForm.toggle()
                } label: {
                    Label("Add Custom Resolution", systemImage: "plus")
                }
                if showCustomDeviceForm {
                    Group {
                        TextField("Device name", text: $customName)
                        TextField("Width (px)", text: $customWidth)
                        TextField("Height (px)", text: $customHeight)
                    }
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    Button("Save Device") {
                        guard let width = Int(customWidth), let height = Int(customHeight),
                              width > 0, height > 0 else { return }
                        let device = DeviceSpec(
                            name: customName.isEmpty ? "\(width)×\(height)" : customName,
                            width: width,
                            height: height,
                            category: .custom
                        )
                        store.addCustomDevice(device)
                        selectedDeviceID = device.id
                        showCustomDeviceForm = false
                    }
                    .disabled(Int(customWidth) == nil || Int(customHeight) == nil)
                }
            } header: {
                Text("Target Device")
            } footer: {
                Text("The resolution determines the image size and generation cost. Bigger screens cost more.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 2: source image

    private var imageStep: some View {
        Form {
            Section {
                if let originalData, let preview = ImageUtil.downsampled(data: originalData, maxPixel: 800) {
                    HStack {
                        Spacer()
                        Image(preview, scale: 1, label: Text("Original"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                } else {
                    Text("Pick or generate the artwork that all 120 wallpapers will be based on.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Original Image")
            }

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Choose a File", systemImage: "folder")
                }
            }

            Section {
                PromptTextArea(placeholder: "Describe the image you want…", text: $generationPrompt)
                Picker("Provider", selection: $providerID) {
                    ForEach(ProviderRegistry.all, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                Button {
                    generateOriginal()
                } label: {
                    if isGenerating {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Generating…")
                        }
                    } else if originalData == nil {
                        Label("Generate", systemImage: "wand.and.stars")
                    } else {
                        Label("Regenerate", systemImage: "wand.and.stars")
                    }
                }
                .disabled(isGenerating || generationPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                if let generationError {
                    Text(generationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("…or Generate with AI")
            } footer: {
                Text("Don't like the result? Adjust the prompt and regenerate as many times as you want.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    originalData = data
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                originalData = try? Data(contentsOf: url)
            }
        }
    }

    private func generateOriginal() {
        guard let provider = ProviderRegistry.provider(id: providerID) else { return }
        let apiKey: String
        switch KeychainStore.readAPIKey(for: provider.id) {
        case .success(let key):
            apiKey = key
        case .failure(let reason):
            generationError = ProviderError.keyUnavailable(providerName: provider.displayName, reason: reason).message
            return
        }
        let size = selectedDevice?.pixelSize ?? CGSize(width: 1024, height: 1024)
        let prompt = generationPrompt
        isGenerating = true
        generationError = nil
        Task {
            do {
                let result = try await provider.generate(prompt: prompt, targetSize: size, apiKey: apiKey)
                originalData = result.data
                if let usage = result.usage {
                    pendingUsage.append(UsageRecord(category: .sourceImage, usage: usage))
                }
            } catch {
                if let usage = (error as? ProviderError)?.usage {
                    pendingUsage.append(UsageRecord(category: .sourceImage, usage: usage, failed: true))
                }
                generationError = error.localizedDescription
            }
            isGenerating = false
        }
    }

    // MARK: - Step 3: review

    private var reviewStep: some View {
        Form {
            Section("Summary") {
                LabeledContent("Name", value: name.isEmpty ? String(localized: "New Wallpaper") : name)
                if let device = selectedDevice {
                    LabeledContent("Device", value: "\(device.name) (\(device.resolutionText))")
                }
                Picker("Provider", selection: $providerID) {
                    ForEach(ProviderRegistry.all, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                LabeledContent("Images to generate", value: "\(WallpaperVariant.all.count)")
            }

            Section {
                Picker("Prompt Style", selection: $templateID) {
                    ForEach(store.allTemplates) { template in
                        Text(template.name).tag(template.id)
                    }
                }
            } footer: {
                Text(store.template(id: templateID).summary)
            }

            if let provider = ProviderRegistry.provider(id: providerID), !KeychainStore.hasAPIKey(for: provider.id) {
                Section {
                    Label("No API key for \(provider.displayName). Add it in Settings.", systemImage: "key.slash")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("120 images will be generated: 30 weather conditions × 4 times of day. You can regenerate any of them later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let creationError {
                Section {
                    Text(creationError).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func createSet() {
        guard let originalData else { return }
        do {
            let meta = SetMetadata(
                device: selectedDevice,
                providerID: providerID,
                createdAt: Date(),
                sourcePrompt: generationPrompt.isEmpty ? nil : generationPrompt,
                promptTemplateID: templateID
            )
            let set = try store.createSet(
                name: name,
                originalData: originalData,
                fileExtension: ImageUtil.fileExtension(for: originalData),
                meta: meta
            )
            if !pendingUsage.isEmpty {
                let records = pendingUsage
                let folderURL = set.folderURL
                Task {
                    await UsageLedgerStore.shared.append(records, folderURL: folderURL)
                    WallpaperStore.shared.refresh()
                }
            }
            center.enqueue(set: set, variants: WallpaperVariant.all)
            dismiss()
        } catch {
            creationError = error.localizedDescription
        }
    }

    // MARK: - Bottom navigation

    private var navigationBar: some View {
        HStack {
            if step != .setup {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .setup
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            switch step {
            case .setup:
                Button("Continue") { step = .image }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDevice == nil)
            case .image:
                Button("Continue") { step = .review }
                    .buttonStyle(.borderedProminent)
                    .disabled(originalData == nil)
            case .review:
                Button {
                    createSet()
                } label: {
                    Label("Create & Generate", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(originalData == nil)
            }
        }
        .padding()
        .background(.bar)
    }
}
