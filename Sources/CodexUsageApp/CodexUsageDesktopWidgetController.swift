import AppKit
import Combine
import CoreGraphics
import CodexUsageCore
import SwiftUI
import UsageCore

private final class CodexUsageDesktopPanel: NSPanel {
    var lockedClickHandler: (() -> Void)?
    var resetSignalBadgeHoverHandler: ((Bool) -> Void)?
    var isResetSignalBadgeAvailable: () -> Bool = { false }
    var dragCompletionHandler: (() -> Void)?
    var resizeHoverHandler: ((Bool) -> Void)?
    var isEditingProvider: () -> Bool = { false }
    var minimumResizeSize = NSSize(width: 300, height: 180)
    private let clickMovementThreshold: CGFloat = 6
    private let resizeHotZoneSize: CGFloat = 28
    private let resetSignalBadgeHotZoneSize = NSSize(width: 220, height: 46)
    private let surfaceInset: CGFloat = 20
    private var isResizeHandleHovered = false
    private var isResetSignalBadgeHovered = false
    private weak var resizeTrackingView: NSView?
    private var resizeTrackingArea: NSTrackingArea?
    private lazy var diagonalResizeCursor: NSCursor = {
        let symbol = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: nil
        )
        let image = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        ) ?? NSCursor.crosshair.image
        image.isTemplate = true
        return NSCursor(
            image: image,
            hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2)
        )
    }()

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           isInBottomRightResizeHotZone(event) {
            trackResize(from: event)
            return
        }
        if event.type == .leftMouseDown,
           isInResetSignalBadgeHotZone(event) {
            super.sendEvent(event)
            return
        }
        if event.type == .leftMouseDown, !isEditingProvider() {
            handleLockedMouseDown(event)
            return
        }
        super.sendEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        if isInBottomRightResizeHotZone(event) {
            trackResize(from: event)
        } else if isInResetSignalBadgeHotZone(event) {
            super.mouseDown(with: event)
        } else if isEditingProvider() {
            super.mouseDown(with: event)
        } else {
            handleLockedMouseDown(event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(for: event)
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(for: event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setResizeHandleHovered(false)
        setResetSignalBadgeHovered(false)
        NSCursor.arrow.set()
        super.mouseExited(with: event)
    }

    func installResizeTrackingArea(on view: NSView) {
        if let resizeTrackingArea, let resizeTrackingView {
            resizeTrackingView.removeTrackingArea(resizeTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved
            ],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        resizeTrackingView = view
        resizeTrackingArea = trackingArea
    }

    private func handleLockedMouseDown(_ event: NSEvent) {
        let initialWindowOrigin = frame.origin
        let initialPointerLocation = convertPoint(
            toScreen: event.locationInWindow
        )
        var maximumMovement: CGFloat = 0

        while let trackingEvent = nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            let pointerLocation = NSEvent.mouseLocation
            let horizontalMovement =
                pointerLocation.x - initialPointerLocation.x
            let verticalMovement =
                pointerLocation.y - initialPointerLocation.y
            let movement = hypot(horizontalMovement, verticalMovement)
            maximumMovement = max(maximumMovement, movement)

            if trackingEvent.type == .leftMouseDragged {
                setFrameOrigin(
                    NSPoint(
                        x: initialWindowOrigin.x + horizontalMovement,
                        y: initialWindowOrigin.y + verticalMovement
                    )
                )
                continue
            }

            if maximumMovement <= clickMovementThreshold {
                lockedClickHandler?()
            } else {
                dragCompletionHandler?()
            }
            return
        }
    }

    private func isInBottomRightResizeHotZone(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let location = event.locationInWindow
        let bounds = contentView.bounds
        let hotZone = NSRect(
            x: bounds.maxX - surfaceInset - resizeHotZoneSize,
            y: bounds.minY + surfaceInset,
            width: resizeHotZoneSize,
            height: resizeHotZoneSize
        )
        return hotZone.contains(location)
    }

    private func isInResetSignalBadgeHotZone(_ event: NSEvent) -> Bool {
        guard isResetSignalBadgeAvailable(), let contentView else {
            return false
        }
        let bounds = contentView.bounds
        let hotZone = NSRect(
            x: bounds.maxX - surfaceInset - resetSignalBadgeHotZoneSize.width,
            y: bounds.maxY - surfaceInset - resetSignalBadgeHotZoneSize.height,
            width: resetSignalBadgeHotZoneSize.width,
            height: resetSignalBadgeHotZoneSize.height
        )
        return hotZone.contains(event.locationInWindow)
    }

    private func updateHover(for event: NSEvent) {
        let isResizeHovered = isInBottomRightResizeHotZone(event)
        let isResetSignalHovered = !isResizeHovered
            && isInResetSignalBadgeHotZone(event)
        setResizeHandleHovered(isResizeHovered)
        setResetSignalBadgeHovered(isResetSignalHovered)
        if isResizeHovered {
            diagonalResizeCursor.set()
        } else if isResetSignalHovered {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func setResizeHandleHovered(_ hovered: Bool) {
        guard hovered != isResizeHandleHovered else { return }
        isResizeHandleHovered = hovered
        resizeHoverHandler?(hovered)
    }

    private func setResetSignalBadgeHovered(_ hovered: Bool) {
        guard hovered != isResetSignalBadgeHovered else { return }
        isResetSignalBadgeHovered = hovered
        resetSignalBadgeHoverHandler?(hovered)
    }

    private func trackResize(from event: NSEvent) {
        guard let initialPointerLocation = eventScreenLocation(event) else {
            return
        }
        let initialFrame = frame
        let topLeftAnchor = NSPoint(
            x: initialFrame.minX,
            y: initialFrame.maxY
        )
        let wasMovable = isMovable
        isMovable = false
        defer { isMovable = wasMovable }
        setResizeHandleHovered(true)
        setResetSignalBadgeHovered(false)
        diagonalResizeCursor.set()

        trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .infinity,
            mode: .eventTracking
        ) { [weak self] trackingEvent, stop in
            guard let self, let trackingEvent else {
                stop.pointee = true
                return
            }
            guard trackingEvent.type != .leftMouseUp else {
                stop.pointee = true
                self.dragCompletionHandler?()
                return
            }
            guard let pointerLocation = self.eventScreenLocation(trackingEvent) else {
                return
            }

            let horizontalMovement =
                pointerLocation.x - initialPointerLocation.x
            let downwardMovement =
                pointerLocation.y - initialPointerLocation.y
            let scale = max(self.backingScaleFactor, 1)
            let width = (
                max(
                    self.minimumResizeSize.width,
                    initialFrame.width + horizontalMovement
                ) * scale
            ).rounded() / scale
            let height = (
                max(
                    self.minimumResizeSize.height,
                    initialFrame.height + downwardMovement
                ) * scale
            ).rounded() / scale
            let resizedFrame = NSRect(
                x: topLeftAnchor.x,
                y: topLeftAnchor.y - height,
                width: width,
                height: height
            )
            self.setFrame(
                resizedFrame,
                display: true,
                animate: false
            )
            self.setFrameTopLeftPoint(topLeftAnchor)
        }
    }

    private func eventScreenLocation(_ event: NSEvent) -> NSPoint? {
        event.cgEvent?.location
    }
}

@MainActor
final class CodexUsageDesktopWidgetController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = CodexUsageDesktopWidgetController()

    @Published private(set) var isVisible = false
    @Published private(set) var isEditing = false
    @Published private(set) var isResizeHandleHovered = false
    @Published private(set) var isResetSignalBadgeHovered = false
    @Published private(set) var palette: CodexUsageWidgetPalette
    @Published private(set) var paceSamples: [CodexUsagePaceSample]

    private var window: NSPanel?
    private weak var viewModel: AgentUsageViewModel?
    private var snapshotObserver: AnyCancellable?
    private let defaults: UserDefaults
    private let originKey = "codexUsage.widget.origin"
    private let frameKey = "codexUsage.widget.frame"
    private let paletteKey = "codexUsage.widget.palette"
    private let paceSamplesKey = "codexUsage.widget.paceSamples"
    private let maximumPaceSamples = 360
    private let initialSize = NSSize(width: 360, height: 220)
    private let minimumSize = NSSize(width: 300, height: 180)
    private let screenMargin: CGFloat = 20
    private var desktopLevel: NSWindow.Level {
        NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        palette = defaults.string(forKey: paletteKey)
            .flatMap(CodexUsageWidgetPalette.init(rawValue:))
            ?? .macaronBerry
        paceSamples = defaults.data(forKey: paceSamplesKey)
            .flatMap {
                try? JSONDecoder().decode(
                    [CodexUsagePaceSample].self,
                    from: $0
                )
            }
            ?? []
        super.init()
    }

    func show(viewModel: AgentUsageViewModel) {
        self.viewModel = viewModel
        observeSnapshots(from: viewModel)

        if let window {
            window.orderFrontRegardless()
            isVisible = true
            return
        }

        let window = CodexUsageDesktopPanel(
            contentRect: initialFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.contentMinSize = minimumSize
        window.minimumResizeSize = minimumSize
        window.lockedClickHandler = { [weak self] in
            self?.openChatGPT()
        }
        window.resetSignalBadgeHoverHandler = { [weak self] isHovered in
            self?.isResetSignalBadgeHovered = isHovered
        }
        window.isResetSignalBadgeAvailable = { [weak self] in
            self?.viewModel?.resetRadar?.activeWatch != nil
        }
        window.dragCompletionHandler = { [weak self] in
            self?.savePosition()
        }
        window.resizeHoverHandler = { [weak self] isHovered in
            self?.isResizeHandleHovered = isHovered
        }
        window.isEditingProvider = { [weak self] in
            self?.isEditing == true
        }
        window.level = desktopLevel
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isMovableByWindowBackground = false
        let hostingView = NSHostingView(
            rootView: CodexUsageDesktopWidgetView(
                viewModel: viewModel,
                controller: self
            )
        )
        window.contentView = hostingView
        window.acceptsMouseMovedEvents = true
        window.installResizeTrackingArea(on: hostingView)
        window.orderFrontRegardless()

        self.window = window
        isVisible = true
    }

    func hide() {
        finishEditing()
        window?.orderOut(nil)
        isResizeHandleHovered = false
        isResetSignalBadgeHovered = false
        isVisible = false
    }

    func beginEditing() {
        guard isVisible else { return }
        isEditing = true
        applyInteractionState()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishEditing() {
        guard isEditing else { return }
        savePosition()
        isEditing = false
        applyInteractionState()
        window?.orderFrontRegardless()
    }

    func toggleEditing() {
        isEditing ? finishEditing() : beginEditing()
    }

    func refresh() {
        viewModel?.refresh()
    }

    func selectPalette(_ palette: CodexUsageWidgetPalette) {
        self.palette = palette
        defaults.set(palette.rawValue, forKey: paletteKey)
    }

    func savePosition() {
        guard let frame = window?.frame else { return }
        defaults.set(NSStringFromPoint(frame.origin), forKey: originKey)
        defaults.set(NSStringFromRect(frame), forKey: frameKey)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        savePosition()
    }

    private func observeSnapshots(from viewModel: AgentUsageViewModel) {
        guard snapshotObserver == nil else { return }
        snapshotObserver = viewModel.$snapshot.sink { [weak self] snapshot in
            self?.recordPaceSample(snapshot)
        }
    }

    private func recordPaceSample(_ snapshot: UsageSnapshot) {
        guard let limit = snapshot.status(for: .codex)?.primaryLimit,
              let resetsAt = limit.resetsAt
        else {
            return
        }

        let collectedSamples = snapshot.codexQuotaHistory.map {
            CodexUsagePaceSample(
                capturedAt: $0.capturedAt,
                usedPercent: $0.usedPercent,
                windowMinutes: $0.windowMinutes,
                resetsAt: $0.resetsAt
            )
        }
        let matchingSamples = (paceSamples + collectedSamples).filter {
            $0.windowMinutes == limit.windowMinutes
                && abs($0.resetsAt.timeIntervalSince(resetsAt))
                    < CodexUsageWidgetPresentation.resetTimeTolerance
        }
        let sample = CodexUsagePaceSample(
            capturedAt: snapshot.generatedAt,
            usedPercent: limit.usedPercent,
            windowMinutes: limit.windowMinutes,
            resetsAt: resetsAt
        )
        paceSamples = compactedPaceSamples(matchingSamples + [sample])
        persistPaceSamples()
    }

    private func compactedPaceSamples(
        _ samples: [CodexUsagePaceSample]
    ) -> [CodexUsagePaceSample] {
        var compacted: [CodexUsagePaceSample] = []
        for sample in samples.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            if let latest = compacted.last,
               latest.usedPercent == sample.usedPercent {
                continue
            }
            if let latest = compacted.last,
               Calendar.current.isDate(
                   latest.capturedAt,
                   equalTo: sample.capturedAt,
                   toGranularity: .minute
               ) {
                compacted[compacted.count - 1] = sample
            } else {
                compacted.append(sample)
            }
        }
        return Array(compacted.suffix(maximumPaceSamples))
    }

    private func persistPaceSamples() {
        guard let data = try? JSONEncoder().encode(paceSamples) else { return }
        defaults.set(data, forKey: paceSamplesKey)
    }

    private func openChatGPT() {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }

    func openResetSource(_ sourceURL: URL) {
        NSWorkspace.shared.open(sourceURL)
    }

    private func applyInteractionState() {
        guard let window else { return }
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.level = isEditing ? .floating : desktopLevel
    }

    private func initialFrame() -> NSRect {
        let screens = NSScreen.screens
        let fallbackScreen = NSScreen.main ?? screens.first
        guard let screen = fallbackScreen else {
            return NSRect(origin: .zero, size: initialSize)
        }

        let defaultFrame = NSRect(
            x: screen.visibleFrame.maxX - screenMargin - initialSize.width,
            y: screen.visibleFrame.maxY - screenMargin - initialSize.height,
            width: initialSize.width,
            height: initialSize.height
        )
        let storedFrame: NSRect
        if let frame = defaults.string(forKey: frameKey).map(NSRectFromString),
           frame.width >= minimumSize.width,
           frame.height >= minimumSize.height {
            storedFrame = normalizedStoredFrame(frame)
        } else if let origin = defaults.string(forKey: originKey)
            .map(NSPointFromString) {
            storedFrame = NSRect(origin: origin, size: initialSize)
        } else {
            return defaultFrame
        }

        let targetScreen = screens.first {
            $0.visibleFrame.intersects(storedFrame)
        } ?? screen
        return CodexUsageWidgetPresentation.clampedFrame(
            storedFrame,
            visibleFrame: targetScreen.visibleFrame,
            margin: screenMargin
        )
    }

    private func normalizedStoredFrame(_ frame: NSRect) -> NSRect {
        guard abs(frame.width - frame.height) < 1 else { return frame }
        return NSRect(
            x: frame.minX,
            y: frame.maxY - initialSize.height,
            width: initialSize.width,
            height: initialSize.height
        )
    }
}
