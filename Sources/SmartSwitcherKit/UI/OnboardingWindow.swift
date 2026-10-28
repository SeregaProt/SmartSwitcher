import AppKit
import SwiftUI

/// Пошаговый мастер первого запуска (раздел 4.4 ТЗ): приветствие и приватность,
/// выдача прав Accessibility с живым статусом, выбор языков детекта, тур по
/// хоткеям. Показывается, пока онбординг не пройден.
public final class OnboardingWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    private let onFinished: () -> Void

    public init(preferences: Preferences, onFinished: @escaping () -> Void) {
        self.preferences = preferences
        self.onFinished = onFinished
    }

    public func show() {
        if window == nil {
            let view = OnboardingView(preferences: preferences) { [weak self] in
                self?.preferences.onboardingCompleted = true
                self?.window?.close()
                self?.window = nil
                self?.onFinished()
            }
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "SmartSwitcher"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            window.level = .floating
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    @ObservedObject var preferences: Preferences
    let onFinish: () -> Void

    @State private var step = 0
    @State private var trusted = PermissionsManager.isTrusted
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)

            Divider()
            HStack {
                ProgressDots(total: totalSteps, current: step)
                Spacer()
                if step > 0 {
                    Button(L10n.text("onb.back", "Назад")) { step -= 1 }
                }
                Button(primaryTitle) { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 1 && !trusted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 460)
        .onReceive(permissionTimer) { _ in
            trusted = PermissionsManager.isTrusted
        }
    }

    private var primaryTitle: String {
        step == totalSteps - 1
            ? L10n.text("onb.start", "Начать работу")
            : L10n.text("onb.next", "Далее")
    }

    private func advance() {
        if step < totalSteps - 1 {
            step += 1
        } else {
            onFinish()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionStep
        case 2: languagesStep
        default: hotkeysStep
        }
    }

    // MARK: - Шаги

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(L10n.text("onb.welcome.title", "Добро пожаловать в SmartSwitcher"))
                .font(.title).bold()
                .multilineTextAlignment(.center)
            Text(L10n.text("onb.welcome.body", "SmartSwitcher автоматически исправляет текст, набранный в неверной раскладке: ghbdtn → привет. Работает незаметно, по завершении слова."))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Label(
                L10n.text("onb.welcome.privacy", "Набранный текст обрабатывается только на этом Mac и никогда не отправляется в сеть."),
                systemImage: "lock.shield"
            )
            .font(.callout)
            .padding(.top, 4)
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("onb.perm.title", "Шаг 1. Доступ к управлению компьютером"))
                .font(.title2).bold()
            Text(L10n.text("onb.perm.body", "Чтобы видеть нажатия клавиш и исправлять раскладку, нужно разрешение «Универсальный доступ» (Accessibility)."))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                stepRow(1, L10n.text("onb.perm.s1", "Нажмите «Открыть настройки»."))
                stepRow(2, L10n.text("onb.perm.s2", "Конфиденциальность и безопасность → Универсальный доступ."))
                stepRow(3, L10n.text("onb.perm.s3", "Включите SmartSwitcher в списке."))
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                Button(L10n.text("onboarding.open", "Открыть настройки")) {
                    PermissionsManager.requestWithPrompt()
                    PermissionsManager.openSystemSettings()
                }
                statusBadge
            }
            Spacer()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(trusted ? .green : .orange)
            Text(trusted
                ? L10n.text("onb.perm.granted", "Доступ выдан")
                : L10n.text("onb.perm.waiting", "Ожидание доступа…"))
                .foregroundColor(.secondary)
        }
        .accessibilityLabel(trusted
            ? L10n.text("onb.perm.granted", "Доступ выдан")
            : L10n.text("onb.perm.waiting", "Ожидание доступа…"))
    }

    private var languagesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("onb.lang.title", "Шаг 2. Языки"))
                .font(.title2).bold()
            Text(L10n.text("onb.lang.body", "Выберите раскладки, между которыми SmartSwitcher будет исправлять. По умолчанию — русская и английская."))
                .foregroundColor(.secondary)
            ForEach(Layout.allCases, id: \.self) { layout in
                Toggle(isOn: languageBinding(layout)) {
                    Text(layout == .ru
                        ? L10n.text("language.ru", "Русский (RU)")
                        : L10n.text("language.en", "English (EN)"))
                }
                .toggleStyle(.checkbox)
            }
            Spacer()
        }
    }

    private var hotkeysStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("onb.keys.title", "Шаг 3. Хоткеи"))
                .font(.title2).bold()
            hotkeyRow("⇧⇧", L10n.text("onb.keys.double", "Двойной Shift — исправить раскладку последнего слова вручную и откатить авто-исправление."))
            hotkeyRow("␣", L10n.text("onb.keys.space", "Пробел/знаки — момент, когда SmartSwitcher проверяет слово и при необходимости исправляет."))
            hotkeyRow("↩", L10n.text("onb.keys.enter", "После Enter авто-исправление не срабатывает (чтобы не править отправленное) — используйте двойной Shift."))
            Text(L10n.text("onb.keys.tip", "Все хоткеи настраиваются в Настройках → Хоткеи."))
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Вспомогательное

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption).bold()
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.secondary.opacity(0.2)))
            Text(text)
        }
    }

    private func hotkeyRow(_ key: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(minWidth: 44, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languageBinding(_ layout: Layout) -> Binding<Bool> {
        Binding(
            get: { preferences.detectionLanguages.contains(layout.rawValue) },
            set: { isOn in
                var set = preferences.detectionLanguages
                if isOn {
                    if !set.contains(layout.rawValue) { set.append(layout.rawValue) }
                } else {
                    set.removeAll { $0 == layout.rawValue }
                }
                if !set.isEmpty { preferences.detectionLanguages = set }
            }
        )
    }
}

private struct ProgressDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Шаг \(current + 1) из \(total)")
    }
}
