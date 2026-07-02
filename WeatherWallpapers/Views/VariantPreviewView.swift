import SwiftUI

/// Immersive gallery viewer over all 120 variants of a set.
/// iOS: native finger-swipe paging, pinch/double-tap zoom, filmstrip.
/// macOS: its own resizable window; two-finger swipes, click-drag paging that
/// moves the actual scroll (neighbour slides in), arrow keys, pinch zoom.
struct VariantPreviewView: View {
    @EnvironmentObject private var store: WallpaperStore
    @EnvironmentObject private var center: GenerationCenter
    @Environment(\.dismiss) private var dismiss

    let setID: String

    @State private var current: WallpaperVariant?
    @State private var extraPrompt = ""
    @State private var showPromptPopover = false
    @State private var showDetails = false

    // Zoom state for the current page.
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var steadyPan: CGSize = .zero

    #if os(macOS)
    // Custom pager state: one offset drives mouse drags, trackpad swipes and
    // keyboard navigation, so neighbouring pages always slide in live.
    @State private var dragOffset: CGFloat = 0
    @State private var mouseDragBase: CGFloat?
    @State private var lastScrollDelta: CGFloat = 0
    @State private var flipGeneration = 0
    @State private var lastLegacyFlip = Date.distantPast
    @State private var pageSize: CGSize = CGSize(width: 1, height: 1)
    @State private var hostWindow: NSWindow?
    @State private var scrollMonitor: Any?
    @State private var stripPos = ScrollPosition(idType: String.self)
    @State private var stripOffsetX: CGFloat = 0
    @State private var stripDragBase: CGFloat?
    #endif

    init(setID: String, variant: WallpaperVariant) {
        self.setID = setID
        _current = State(initialValue: variant)
    }

    private var variant: WallpaperVariant { current ?? WallpaperVariant.all[0] }
    private var currentIndex: Int { WallpaperVariant.all.firstIndex(of: variant) ?? 0 }

    var body: some View {
        Group {
            if let set = store.set(id: setID) {
                // Dedicated rows: the filmstrip and the bars never cover the image.
                VStack(spacing: 0) {
                    topBar(set)
                    pager(set)
                    bottomPanel(set)
                }
                .sheet(isPresented: $showDetails) {
                    VariantDetailsView(set: set, variant: variant)
                        #if os(iOS)
                        .presentationDetents([.medium, .large])
                        #endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: current) {
            resetZoom()
        }
        #if os(macOS)
        .frame(minWidth: 940, minHeight: 700)
        .background(keyboardShortcuts)
        #endif
    }

    // MARK: - Pager

    @ViewBuilder
    private func pager(_ set: WallpaperSet) -> some View {
        #if os(macOS)
        pagerMac(set)
        #else
        pagerIOS(set)
        #endif
    }

    #if os(iOS)
    private func pagerIOS(_ set: WallpaperSet) -> some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    // id: \.self — the scrollPosition binding is a WallpaperVariant?,
                    // so the row identity must be the variant itself.
                    ForEach(WallpaperVariant.all, id: \.self) { item in
                        page(item, in: set, pageSize: geo.size)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.never)
            .scrollDisabled(zoom > 1.02)
            // Gestures live on the stationary scroll view, not on the moving
            // pages — attaching them to a view that moves with the gesture
            // makes the translation oscillate (jitter).
            .simultaneousGesture(magnifyGesture(pageSize: geo.size))
            .simultaneousGesture(iosPanGesture(pageSize: geo.size), including: zoom > 1.02 ? .all : .subviews)
        }
    }
    #endif

    #if os(macOS)
    private func pagerMac(_ set: WallpaperSet) -> some View {
        GeometryReader { geo in
            // The gestures are attached to this stationary ZStack — attaching
            // them to the moving HStack makes the drag translation oscillate.
            ZStack {
                HStack(spacing: 0) {
                    pageOrEmpty(currentIndex - 1, in: set, size: geo.size)
                    pageOrEmpty(currentIndex, in: set, size: geo.size)
                    pageOrEmpty(currentIndex + 1, in: set, size: geo.size)
                }
                // The ZStack centers the 3-page strip, so the middle (current)
                // page sits in the viewport at offset 0 — dragOffset is the
                // only displacement. An extra -width here shows the neighbour.
                .offset(x: dragOffset)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(macDragGesture())
            .simultaneousGesture(magnifyGesture(pageSize: geo.size))
            .onAppear { pageSize = geo.size }
            .onChange(of: geo.size) { _, size in pageSize = size }
        }
        .clipped()
        .background(WindowAccessor(window: $hostWindow))
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
    }

    @ViewBuilder
    private func pageOrEmpty(_ index: Int, in set: WallpaperSet, size: CGSize) -> some View {
        if WallpaperVariant.all.indices.contains(index) {
            page(WallpaperVariant.all[index], in: set, pageSize: size)
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }
    #endif

    @ViewBuilder
    private func page(_ item: WallpaperVariant, in set: WallpaperSet, pageSize: CGSize) -> some View {
        let isCurrent = item == variant
        ZStack {
            if set.hasImage(for: item) {
                ThumbnailView(url: set.url(for: item), maxPixel: 2000)
                    .aspectRatio(cellAspect(set), contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.12))
                    .aspectRatio(cellAspect(set), contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                            .foregroundStyle(.white.opacity(0.25))
                    )
                    .overlay(
                        VStack(spacing: 14) {
                            Image(systemName: item.weather.symbolName)
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("Not generated yet")
                                .foregroundStyle(.white.opacity(0.75))
                            Button {
                                center.enqueue(set: set, variants: [item])
                            } label: {
                                Label("Generate", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    )
                    .padding(24)
            }

            if let state = center.state(setID: setID, variant: item), state == .running || state == .queued {
                Color.black.opacity(0.4)
                ProgressView().tint(.white)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .scaleEffect(isCurrent ? zoom : 1)
        .offset(isCurrent ? pan : .zero)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.spring(duration: 0.3)) {
                if zoom > 1.02 {
                    resetZoom()
                } else {
                    zoom = 2.5
                    steadyZoom = 2.5
                }
            }
        }
    }

    // MARK: - Gestures

    private func magnifyGesture(pageSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(steadyZoom * value.magnification, 1), 5)
            }
            .onEnded { _ in
                if zoom < 1.05 {
                    withAnimation(.spring(duration: 0.25)) { resetZoom() }
                } else {
                    steadyZoom = zoom
                    clampPan(pageSize: pageSize)
                }
            }
    }

    #if os(iOS)
    private func iosPanGesture(pageSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1.02 else { return }
                pan = CGSize(
                    width: steadyPan.width + value.translation.width,
                    height: steadyPan.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard zoom > 1.02 else { return }
                clampPan(pageSize: pageSize)
            }
    }
    #endif

    #if os(macOS)
    private func macDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                if zoom > 1.02 {
                    pan = CGSize(
                        width: steadyPan.width + value.translation.width,
                        height: steadyPan.height + value.translation.height
                    )
                } else {
                    // Base captured on the first change, so a drag that starts
                    // mid-animation picks up from the current position.
                    if mouseDragBase == nil { mouseDragBase = dragOffset }
                    dragOffset = rubberBanded((mouseDragBase ?? 0) + value.translation.width)
                }
            }
            .onEnded { value in
                if zoom > 1.02 {
                    clampPan(pageSize: pageSize)
                } else {
                    let inertia = value.predictedEndTranslation.width - value.translation.width
                    mouseDragBase = nil
                    settle(projected: dragOffset + inertia)
                }
            }
    }

    /// Resistance at the first/last page.
    private func rubberBanded(_ offset: CGFloat) -> CGFloat {
        let atStart = currentIndex == 0 && offset > 0
        let atEnd = currentIndex == WallpaperVariant.all.count - 1 && offset < 0
        return (atStart || atEnd) ? offset * 0.3 : offset
    }

    /// Finishes a drag/swipe: picks the target page and animates to it.
    private func settle(projected: CGFloat) {
        var direction = 0
        if projected < -pageSize.width * 0.22 { direction = 1 }
        if projected > pageSize.width * 0.22 { direction = -1 }
        if !WallpaperVariant.all.indices.contains(currentIndex + direction) { direction = 0 }
        animatePage(direction)
    }

    /// Interruption-safe paging: the page index swaps *immediately* (with the
    /// offset compensated so nothing jumps on screen), then the strip animates
    /// home. State and screen can never drift apart, and a new drag or key
    /// press mid-animation simply retargets the offset.
    private func animatePage(_ direction: Int) {
        let newIndex = currentIndex + direction
        guard direction != 0, WallpaperVariant.all.indices.contains(newIndex) else {
            withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
            return
        }
        flipGeneration += 1
        let generation = flipGeneration
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            current = WallpaperVariant.all[newIndex]
            dragOffset += CGFloat(direction) * pageSize.width
        }
        // Next runloop pass: guarantees the compensated offset above is
        // committed as its own frame before the slide-home animation starts.
        // The generation check makes sure that when flips arrive in a burst,
        // only the newest one animates home — stale ones would otherwise race
        // and strand the offset a full page away (screen ≠ selected state).
        DispatchQueue.main.async {
            guard generation == flipGeneration else { return }
            withAnimation(.spring(duration: 0.28)) {
                dragOffset = 0
            }
        }
    }

    // MARK: - Trackpad scroll events

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let hostWindow, event.window === hostWindow else { return event }
            return handleScroll(event) ? nil : event
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
    }

    /// Two-finger swipes drive the same dragOffset as mouse drags; while
    /// zoomed in they pan the image instead. Returns true when consumed.
    private func handleScroll(_ event: NSEvent) -> Bool {
        // Events over the bottom panel belong to the filmstrip's own scroll view.
        if event.locationInWindow.y < 140 { return false }
        if zoom > 1.02 {
            pan.width += event.scrollingDeltaX
            pan.height += event.scrollingDeltaY
            steadyPan = pan
            if event.phase == .ended || event.momentumPhase == .ended {
                clampPan(pageSize: pageSize)
            }
            return true
        }

        // Ignore inertia — the page settles on gesture end.
        if event.momentumPhase != [] {
            return true
        }

        switch event.phase {
        case .began:
            lastScrollDelta = 0
            // Capture the base so the swipe continues from wherever the strip
            // currently is (it may still be animating home).
            mouseDragBase = dragOffset
            return true
        case .changed:
            lastScrollDelta = event.scrollingDeltaX
            let base = (mouseDragBase ?? dragOffset) + event.scrollingDeltaX
            mouseDragBase = base
            dragOffset = rubberBanded(base)
            return true
        case .ended, .cancelled:
            mouseDragBase = nil
            settle(projected: dragOffset + lastScrollDelta * 12)
            return true
        default:
            // Legacy mouse wheels report no phases — treat a tick as a page
            // flip, debounced: wheels emit bursts of ticks and flipping on
            // every one floods the pager and desyncs it.
            if event.phase == [] && event.momentumPhase == [] {
                let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
                if abs(delta) > 1, Date().timeIntervalSince(lastLegacyFlip) > 0.35 {
                    lastLegacyFlip = Date()
                    animatePage(delta < 0 ? 1 : -1)
                }
                return true
            }
            return true
        }
    }
    #endif

    private func clampPan(pageSize: CGSize) {
        let maxX = pageSize.width * (zoom - 1) / 2
        let maxY = pageSize.height * (zoom - 1) / 2
        withAnimation(.spring(duration: 0.25)) {
            pan = CGSize(
                width: min(max(pan.width, -maxX), maxX),
                height: min(max(pan.height, -maxY), maxY)
            )
        }
        steadyPan = pan
    }

    private func resetZoom() {
        zoom = 1
        steadyZoom = 1
        pan = .zero
        steadyPan = .zero
    }

    private func go(to newIndex: Int) {
        guard WallpaperVariant.all.indices.contains(newIndex) else { return }
        #if os(macOS)
        let step = newIndex - currentIndex
        if abs(step) == 1 {
            animatePage(step)
        } else if step != 0 {
            // Distant jumps (filmstrip) switch instantly.
            current = WallpaperVariant.all[newIndex]
            dragOffset = 0
        }
        #else
        withAnimation(.snappy(duration: 0.25)) {
            current = WallpaperVariant.all[newIndex]
        }
        #endif
    }

    #if os(macOS)
    /// Invisible buttons carrying the arrow-key and escape shortcuts.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { go(to: currentIndex - 1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { go(to: currentIndex + 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
    #endif

    // MARK: - Top bar

    private func topBar(_ set: WallpaperSet) -> some View {
        HStack(spacing: 12) {
            #if os(macOS)
            // The window's own traffic lights live here (hidden title bar).
            Color.clear.frame(width: 64, height: 32)
            #else
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            #endif

            Spacer()

            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    Label(variant.weather.localizedName, systemImage: variant.weather.symbolName)
                    Label(variant.time.localizedName, systemImage: variant.time.symbolName)
                }
                .font(.headline)
                HStack(spacing: 6) {
                    Text(verbatim: "\(currentIndex + 1) / \(WallpaperVariant.all.count)")
                    // iPhone keeps the bar minimal — size and cost live in
                    // the Details sheet behind the ellipsis menu.
                    if showsInlineInfo, let info = inlineInfo(set) {
                        Text(verbatim: "· \(info)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer()

            actionsMenu(set)
                #if os(macOS)
                .padding(.trailing, 32)
                #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var showsInlineInfo: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// "2.4 MB · $0.078" for the current image, nil when there is nothing to show.
    private func inlineInfo(_ set: WallpaperSet) -> String? {
        var parts: [String] = []
        if set.hasImage(for: variant),
           let size = try? FileManager.default.attributesOfItem(atPath: set.url(for: variant).path)[.size] as? Int {
            parts.append(UsageFormat.fileSize(size))
        }
        let records = set.usage.records(variant: variant.baseName)
        if !records.isEmpty {
            parts.append(UsageFormat.cost(records.totalCost))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func actionsMenu(_ set: WallpaperSet) -> some View {
        let state = center.state(setID: setID, variant: variant)
        let busy = state == .running || state == .queued
        return Menu {
            Button {
                showDetails = true
            } label: {
                Label("Details…", systemImage: "info.circle")
            }

            Divider()

            Button {
                center.clearFailures(setID: set.id)
                center.enqueue(set: set, variants: [variant])
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .disabled(busy)

            Button {
                showPromptPopover = true
            } label: {
                Label("Regenerate with Instructions…", systemImage: "text.badge.star")
            }
            .disabled(busy)

            #if os(macOS)
            if set.hasImage(for: variant) {
                Divider()
                Button {
                    Platform.revealInFinder(set.url(for: variant))
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
            #endif

            if set.hasImage(for: variant) {
                Divider()
                Button(role: .destructive) {
                    store.deleteImage(of: set, variant: variant)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
            promptPopover(set)
        }
    }

    private func promptPopover(_ set: WallpaperSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Extra instructions")
                .font(.headline)
            PromptTextArea(
                placeholder: "e.g. make the moon bigger…",
                text: $extraPrompt,
                minHeight: 60,
                maxHeight: 100
            )
            // Changing the style here persists to the set — it applies to this
            // regeneration and every future one.
            Picker("Prompt Style", selection: Binding(
                get: { store.template(id: set.meta.promptTemplateID).id },
                set: { store.setPromptTemplate($0, for: set) }
            )) {
                ForEach(store.allTemplates) { template in
                    Text(template.name).tag(template.id)
                }
            }
            HStack {
                Spacer()
                Button {
                    showPromptPopover = false
                    center.clearFailures(setID: set.id)
                    // Re-fetch the set: the picker above may have just rewritten its metadata.
                    center.enqueue(set: store.set(id: setID) ?? set, variants: [variant], extraPrompt: extraPrompt)
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Bottom panel

    private func bottomPanel(_ set: WallpaperSet) -> some View {
        VStack(spacing: 10) {
            if case .failed(let message) = center.state(setID: setID, variant: variant) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            filmstrip(set)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Filmstrip

    private let stripHeight: CGFloat = 54

    /// Weather-grouped thumbnails, mirroring the detail screen sections.
    /// A plain (non-lazy) HStack: scrollTo(id:) must be able to reach
    /// off-screen thumbnails, and lazy containers don't instantiate them.
    private func stripContent(_ set: WallpaperSet, aspect: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(WeatherCondition.allCases) { weather in
                VStack(alignment: .leading, spacing: 5) {
                    Label(weather.localizedName, systemImage: weather.symbolName)
                        .font(.caption2)
                        .foregroundStyle(variant.weather == weather ? .primary : .secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        ForEach(WallpaperVariant.variants(for: weather)) { item in
                            filmstripCell(item, in: set, aspect: aspect, height: stripHeight)
                                .id("strip-\(item.id)")
                                .onTapGesture {
                                    go(to: WallpaperVariant.all.firstIndex(of: item) ?? 0)
                                }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    #if os(macOS)
    private func filmstrip(_ set: WallpaperSet) -> some View {
        let aspect = cellAspect(set)
        return ScrollView(.horizontal) {
            stripContent(set, aspect: aspect)
                .scrollTargetLayout()
        }
        .scrollPosition($stripPos)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, newX in
            stripOffsetX = newX
        }
        // Click-drag scrolling for the strip (native scroll views only follow
        // two-finger gestures on the Mac).
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if stripDragBase == nil { stripDragBase = stripOffsetX }
                    stripPos.scrollTo(x: (stripDragBase ?? 0) - value.translation.width)
                }
                .onEnded { _ in
                    stripDragBase = nil
                }
        )
        .scrollIndicators(.never)
        .frame(height: stripHeight + 30)
        .onChange(of: current) {
            withAnimation(.snappy(duration: 0.25)) {
                stripPos.scrollTo(id: "strip-\(variant.id)", anchor: .center)
            }
        }
        .onAppear {
            stripPos.scrollTo(id: "strip-\(variant.id)", anchor: .center)
        }
    }
    #else
    private func filmstrip(_ set: WallpaperSet) -> some View {
        let aspect = cellAspect(set)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                stripContent(set, aspect: aspect)
            }
            .scrollIndicators(.never)
            .frame(height: stripHeight + 30)
            .onChange(of: current) {
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo("strip-\(variant.id)", anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo("strip-\(variant.id)", anchor: .center)
            }
        }
    }
    #endif

    @ViewBuilder
    private func filmstripCell(_ item: WallpaperVariant, in set: WallpaperSet, aspect: CGFloat, height: CGFloat) -> some View {
        let isCurrent = item == variant
        ZStack {
            if set.hasImage(for: item) {
                ThumbnailView(url: set.url(for: item), maxPixel: 160)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .overlay(
                        Image(systemName: item.time.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    )
            }
            if case .failed = center.state(setID: setID, variant: item) {
                Circle().fill(.red).frame(width: 6, height: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(3)
            }
        }
        .frame(width: height * aspect, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isCurrent ? Color.white : .white.opacity(0.15), lineWidth: isCurrent ? 2.5 : 1)
        )
        .opacity(isCurrent ? 1 : 0.55)
        .scaleEffect(isCurrent ? 1.12 : 1)
        .animation(.snappy(duration: 0.2), value: isCurrent)
    }

    private func cellAspect(_ set: WallpaperSet) -> CGFloat {
        guard let device = set.meta.device, device.height > 0 else { return 9.0 / 16.0 }
        return CGFloat(device.width) / CGFloat(device.height)
    }
}
