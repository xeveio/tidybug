import AppKit
import SwiftUI

/// Notch overlay: live CPU / memory in two "wings" either side of the camera
/// housing, expanding into a small dashboard on hover. Lives in a borderless,
/// non-activating panel above the menu bar, so it stays visible when the
/// TidyBug window is closed (the app keeps running for its menu bar extra).
enum NotchSupport {
    @MainActor static var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }
    @MainActor static var hasNotch: Bool { notchScreen != nil }
}

struct NotchGeometry: Equatable {
    var hasNotch = false
    /// Width of the camera cutout.
    var notchWidth: CGFloat = 0
    /// Menu bar / notch height.
    var barHeight: CGFloat = 24
    /// Width of each wing beside the notch.
    var wing: CGFloat = 78
    /// Concave flare where the shape meets the top edge of the screen.
    static let flare: CGFloat = 8

    var collapsedSize: CGSize {
        hasNotch ? CGSize(width: notchWidth + 2 * wing, height: barHeight)
                 : CGSize(width: 2 * wing + 30, height: 28)
    }

    var expandedSize: CGSize {
        CGSize(width: max(440, collapsedSize.width + 24), height: (hasNotch ? barHeight : 28) + 184)
    }

    /// Panel size: room for the expanded shape, its flares and its shadow.
    var canvas: CGSize {
        CGSize(width: expandedSize.width + 2 * Self.flare + 60, height: expandedSize.height + 40)
    }
}

@MainActor @Observable
final class NotchState {
    var expanded = false
    var geometry = NotchGeometry()
    var confirmClean = false
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Buttons work on the first click without activating TidyBug.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchController {
    static let shared = NotchController()

    let state = NotchState()
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var sampling = false
    private var started = false
    private var applied: Settings?

    struct Settings: Equatable {
        var enabled: Bool
        var metrics: String
        var expandOnHover: Bool
    }

    private var settings: Settings {
        let d = UserDefaults.standard
        return Settings(enabled: d.object(forKey: "notchEnabled") as? Bool ?? NotchSupport.hasNotch,
                        metrics: d.string(forKey: "notchMetrics") ?? "cpuMem",
                        expandOnHover: d.object(forKey: "notchExpandOnHover") as? Bool ?? true)
    }

    // MARK: Lifecycle

    func startIfEnabled() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applied = nil
                self?.apply()
            }
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleFullScreenCheck() }
            })
        }
        apply()
    }

    /// Re-reads settings; cheap when nothing relevant changed.
    func apply() {
        let s = settings
        guard s != applied else { return }
        applied = s
        if s.enabled { show(s) } else { hide() }
    }

    private func show(_ s: Settings) {
        if panel == nil { build() }
        layout(wide: s.metrics == "cpuMemNet")
        if !sampling {
            SystemMonitor.shared.start()
            sampling = true
        }
        if monitors.isEmpty { installMouseTracking() }
        updateFullScreen()
    }

    private func hide() {
        panel?.orderOut(nil)
        if sampling {
            SystemMonitor.shared.stop()
            sampling = false
        }
        removeMouseTracking()
        state.expanded = false
    }

    private func build() {
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        let host = FirstMouseHostingView(rootView: NotchView(state: state))
        host.sizingOptions = []
        p.contentView = host
        panel = p
    }

    private var screen: NSScreen? { NotchSupport.notchScreen ?? NSScreen.main }

    private func layout(wide: Bool) {
        guard let panel, let screen else { return }
        var g = NotchGeometry()
        var centerX = screen.frame.midX
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            g.hasNotch = true
            g.notchWidth = screen.frame.width - left.width - right.width
            g.barHeight = screen.safeAreaInsets.top
            // Widths only, so this holds whether the aux areas are screen-local or global.
            centerX = screen.frame.minX + left.width + g.notchWidth / 2
        } else {
            g.barHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
        g.wing = wide ? 124 : 78
        state.geometry = g
        let canvas = g.canvas
        let top = g.hasNotch ? screen.frame.maxY : screen.frame.maxY - g.barHeight - 6
        panel.setFrame(NSRect(x: centerX - canvas.width / 2, y: top - canvas.height,
                              width: canvas.width, height: canvas.height), display: true)
    }

    // MARK: Hover

    private func installMouseTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { monitors.append(local) }
    }

    private func removeMouseTracking() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// The visible shape in screen coordinates.
    private func visibleRect(expanded: Bool) -> NSRect? {
        guard let panel else { return nil }
        let g = state.geometry
        let size = expanded ? g.expandedSize : g.collapsedSize
        let f = panel.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    private func isMouseInside(expanded: Bool) -> Bool {
        visibleRect(expanded: expanded)?.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) ?? false
    }

    private func mouseMoved() {
        guard let panel, panel.isVisible else { return }
        let inside = isMouseInside(expanded: state.expanded)
        // Clicks outside the shape go straight through to whatever is underneath.
        panel.ignoresMouseEvents = !inside
        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            guard !state.expanded, hoverTask == nil, applied?.expandOnHover ?? true else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                self.hoverTask = nil
                if self.isMouseInside(expanded: false) { self.setExpanded(true) }
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil
            guard state.expanded, collapseTask == nil else { return }
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard let self, !Task.isCancelled else { return }
                self.collapseTask = nil
                if !self.isMouseInside(expanded: true) { self.setExpanded(false) }
            }
        }
    }

    func setExpanded(_ on: Bool) {
        state.expanded = on
        if !on { state.confirmClean = false }
        panel?.ignoresMouseEvents = !isMouseInside(expanded: on)
    }

    // MARK: Full screen

    private func scheduleFullScreenCheck() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.updateFullScreen()
        }
    }

    private func updateFullScreen() {
        guard let panel, applied?.enabled == true else { return }
        if frontAppIsFullScreen() {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// The menu bar hides for full-screen apps; so do we. Detected as a
    /// layer-0 window of the frontmost app covering the whole screen.
    private func frontAppIsFullScreen() -> Bool {
        guard let screen, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let target = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict) else { return false }
            return rect.integral == target.integral
        }
    }

    // MARK: Actions

    func openApp(pane: Pane? = nil) {
        if let pane { AppModel.shared.pane = pane }
        setExpanded(false)
        NSApp.activate()
        // Re-opening our own bundle sends a reopen event, which brings the
        // main window back even after it was closed.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
    }

    func cleanSafeTapped() {
        if state.confirmClean {
            state.confirmClean = false
            Task { await AppModel.shared.cleanSafeJunk() }
        } else {
            state.confirmClean = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.state.confirmClean = false
            }
        }
    }
}
