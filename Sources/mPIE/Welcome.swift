import AppKit
import SwiftUI
import mPIECore

/// Premier lancement : deux autorisations, le lanceur de départ déjà posé, un seul appel principal (COMMENCER).
struct WelcomeView: View {
    let launcherCount: Int
    let hotkey: String
    let start: () -> Void
    @State private var trusted = KeySender.trusted

    var body: some View {
        VStack(spacing: Socle.M.space4) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text(branded: L("welcome.title")).socle(Socle.T.display).foregroundStyle(Socle.C.textStrong)
            Text(branded: L("welcome.text")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Socle.M.space2) {
                step("welcome.access", "welcome.access.text") {
                    if trusted { Text(L("welcome.done")).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.success) }
                    else {
                        Button(L("welcome.authorize")) { KeySender.requestTrust() }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    }
                }
                step("welcome.launcher", "welcome.launcher.text") {
                    Text(launcherCount > 0 ? L("welcome.launcher.count", launcherCount) : L("welcome.launcher.none")).socle(Socle.T.labelStrong)
                        .foregroundStyle(launcherCount > 0 ? Socle.C.success : Socle.C.textMuted)
                }
                step("welcome.automation", "welcome.automation.text") {
                    Text(L("welcome.later")).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textMuted)
                }
            }
            HStack(spacing: Socle.M.space2) {
                Text(L("welcome.try")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                Text(hotkey).socle(Socle.T.monoSm).foregroundStyle(Socle.C.textStrong)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Socle.C.control, in: RoundedRectangle(cornerRadius: 3))
            }
            Button(L("welcome.start")) { start() }
                .buttonStyle(SocleButtonStyle(.action)).fixedSize()
        }
        .padding(Socle.M.space6)
        .frame(width: 540)
        .background(Socle.C.surface)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in trusted = KeySender.trusted }
    }

    private func step<C: View>(_ title: String, _ text: String, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack(spacing: Socle.M.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                Text(L(text)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Socle.M.space2)
            trailing()
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surfaceRaised).overlay(Rectangle().stroke(Socle.C.border))
    }
}

@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show(launcherCount: Int, hotkey: String, quietly: Bool = false, done: @escaping () -> Void) {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = L("welcome.window")
        let host = NSHostingView(rootView: WelcomeView(launcherCount: launcherCount, hotkey: hotkey, start: {
            window?.close(); window = nil; done()
        }))
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.socleCenter()
        window = w
        if quietly { w.orderFront(nil) } else { w.present() }
    }

    static func view(launcherCount: Int, hotkey: String) -> NSView {
        NSHostingView(rootView: WelcomeView(launcherCount: launcherCount, hotkey: hotkey, start: {}))
    }
}
