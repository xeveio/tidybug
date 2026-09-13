import SwiftUI
import TidyBugCore
import UserNotifications

// MARK: - State

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case meet, promise, access, notify, prefs, ready
    var id: Int { rawValue }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    var title: String {
        switch self {
        case .meet: "Welcome"
        case .promise: "Safety model"
        case .access: "Full Disk Access"
        case .notify: "Notifications"
        case .prefs: "Preferences"
        case .ready: "Ready"
        }
    }

    var caption: String {
        switch self {
        case .meet: "What TidyBug does"
        case .promise: "How your files are protected"
        case .access: "Required for complete scans"
        case .notify: "Low-space alerts"
        case .prefs: "Menu bar, login, projects"
        case .ready: "Run the first scan"
        }
    }
}

@MainActor @Observable
final class OnboardingState {
    var step: OnboardingStep
    var forward = true
    var fullDiskAccess = AppModel.checkFullDiskAccess()
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    init(step: OnboardingStep) { self.step = step }

    func go(_ target: OnboardingStep) {
        guard target != step else { return }
        forward = target.rawValue > step.rawValue
        withAnimation(.easeOut(duration: 0.2)) { step = target }
        UserDefaults.standard.set(target.rawValue, forKey: "onboardingStep")
    }

    func refreshNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        withAnimation(.tidy) { notificationStatus = status }
    }

    @discardableResult
    func requestNotifications() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshNotificationStatus()
        return granted
    }

    var notificationsAllowed: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }
}

// MARK: - Container

/// First-run setup assistant: step rail on the left, step content on the right.
/// Resumes where it left off, because granting Full Disk Access usually makes
/// macOS relaunch the app.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var state = OnboardingState(
        step: OnboardingStep(rawValue: UserDefaults.standard.integer(forKey: "onboardingStep")) ?? .meet)
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            OnboardingRail(state: state)
                .frame(width: 300)
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    if state.step != .ready {
                        Button("Skip setup") { finish(startScan: false) }.buttonStyle(.tidyQuiet)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 52)
                .background(WindowDragArea())

                ScrollView {
                    ZStack(alignment: .topLeading) {
                        stepContent
                            .id(state.step)
                            .transition(stepTransition)
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 56)
                    .padding(.top, 36)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)

                footer
            }
            .frame(maxWidth: .infinity)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) { primaryAction(); return .handled }
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) {
            if let p = state.step.previous { state.go(p) }
            return .handled
        }
        .onKeyPress(.escape) {
            if let p = state.step.previous { state.go(p) }
            return .handled
        }
        .onAppear { focused = true }
        .task { await state.refreshNotificationStatus() }
        .task(id: state.step) {
            guard state.step == .access else { return }
            while !Task.isCancelled {
                let granted = AppModel.checkFullDiskAccess()
                if granted != state.fullDiskAccess {
                    withAnimation(.bouncy) { state.fullDiskAccess = granted }
                    if granted { AppModel.shared.refreshVolume() }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch state.step {
        case .meet: MeetStep()
        case .promise: PromiseStep()
        case .access: AccessStep(state: state)
        case .notify: NotifyStep(state: state)
        case .prefs: PrefsStep()
        case .ready: ReadyStep(state: state) { finish(startScan: true) }
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let dx: CGFloat = state.forward ? 18 : -18
        return .asymmetric(insertion: .offset(x: dx).combined(with: .opacity), removal: .opacity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let previous = state.step.previous {
                Button { state.go(previous) } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.tidyQuiet)
            }
            Spacer()
            Text("\(state.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.mono(11.5))
                .foregroundStyle(Palette.textTertiary)
                .contentTransition(.numericText())
            if state.step == .access && !state.fullDiskAccess {
                Button("Skip for now") { advance() }.buttonStyle(.tidySecondary)
            } else if state.step != .ready {
                Button { advance() } label: {
                    HStack(spacing: 8) {
                        Text("Continue")
                        Text("↵").font(.system(size: 11, weight: .medium)).opacity(0.7)
                    }
                }
                .buttonStyle(.tidy)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        .animation(.tidy, value: state.fullDiskAccess)
    }

    private func advance() {
        if let next = state.step.next { state.go(next) }
    }

    private func primaryAction() {
        if state.step == .ready { finish(startScan: true) } else { advance() }
    }

    private func finish(startScan: Bool) {
        UserDefaults.standard.removeObject(forKey: "onboardingStep")
        onFinish()
        let model = AppModel.shared
        model.pane = .home
        if startScan { model.startSmartScan() }
    }
}

// MARK: - Rail

/// Left rail: brand, vertical step list with progress, version.
struct OnboardingRail: View {
    let state: OnboardingState

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowDragArea().frame(height: 52)
            HStack(spacing: 9) {
                LogoMark(state: state.step == .ready ? .celebrating : .idle, size: 20)
                Text("TidyBug").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Setup").font(.system(size: 15)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(OnboardingStep.allCases) { step in
                    StepRow(step: step, current: state.step,
                            isLast: step == OnboardingStep.allCases.last,
                            accessGranted: state.fullDiskAccess) {
                        if step.rawValue < state.step.rawValue { state.go(step) }
                    }
                }
            }
            .padding(.horizontal, 26)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("All settings can be changed later in Settings (⌘,).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                Text(version).font(.mono(11)).foregroundStyle(Palette.textTertiary)
            }
            .padding(26)
        }
        .frame(maxHeight: .infinity)
        .background(Palette.surface.opacity(0.55))
    }
}

struct StepRow: View {
    let step: OnboardingStep
    let current: OnboardingStep
    let isLast: Bool
    let accessGranted: Bool
    let jump: () -> Void

    private var done: Bool { step.rawValue < current.rawValue }
    private var isCurrent: Bool { step == current }
    /// Access step completed without permission shows a warning marker.
    private var skipped: Bool { done && step == .access && !accessGranted }

    var body: some View {
        Button(action: jump) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    indicator
                    if !isLast {
                        Rectangle()
                            .fill(done ? Palette.success.opacity(0.6) : Palette.border)
                            .frame(width: 1.5, height: 30)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? Palette.text : (done ? Palette.textSecondary : Palette.textTertiary))
                    Text(skipped ? "Skipped — scans will be partial" : step.caption)
                        .font(.system(size: 11.5))
                        .foregroundStyle(skipped ? Palette.warning : Palette.textTertiary)
                }
                .padding(.top, 1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!done)
        .animation(.tidy, value: current)
    }

    @ViewBuilder
    private var indicator: some View {
        ZStack {
            if skipped {
                Circle().fill(Palette.warning.opacity(0.15))
                Image(systemName: "exclamationmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.warning)
            } else if done {
                Circle().fill(Palette.success)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black)
                    .transition(.scale.combined(with: .opacity))
            } else if isCurrent {
                Circle().strokeBorder(Palette.accent, lineWidth: 1.5)
                Circle().fill(Palette.accent).frame(width: 7, height: 7)
            } else {
                Circle().strokeBorder(Palette.borderStrong, lineWidth: 1.2)
                Text("\(step.rawValue + 1)").font(.mono(9.5, weight: .medium)).foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(width: 20, height: 20)
    }
}
