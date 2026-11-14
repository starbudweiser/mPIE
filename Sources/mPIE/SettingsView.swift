import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import mPIECore

enum SettingsTab: String, CaseIterable { case general, trigger, presets, launcher, controller, music, updates }

@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var router = SettingsRouter.shared
    @ObservedObject var launcher: LauncherStore
    @ObservedObject var controls: ControlStore
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var apps: [RunningEntry] = []
    @State private var found: [String: [String]] = [:]
    @State private var pendingReplace: LauncherPreset?
    @State private var notice: String?
    @State private var selectedSet = ControlDefaults.genericID
    @State private var trusted = KeySender.trusted

    struct RunningEntry: Identifiable { let id: String; let name: String; let icon: NSImage? }

    var body: some View {
        VStack(spacing: 0) {
            SocleSegmented(options: SettingsTab.allCases, selection: router.tab, label: { L("settings.tab." + $0.rawValue) }, onSelect: { router.tab = $0 })
                .padding(Socle.M.space3)
            Divider().overlay(Socle.C.border)
            ScrollView {
                VStack(alignment: .leading, spacing: Socle.M.space4) {
                    switch router.tab {
                    case .general: general
                    case .trigger: trigger
                    case .presets: presets
                    case .launcher: launcherTab
                    case .controller: controller
                    case .music: music
                    case .updates: updates
                    }
                }
                .padding(Socle.M.space4).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Socle.C.bg)
        .frame(width: 860, height: 680)
        .onAppear { reloadApps(); reloadFound() }
    }

    // MARK: Général

    private var general: some View {
        SocleModuleGrid(minimum: 380) {
            block("settings.system") {
                toggle("settings.menubar", $prefs.menuBarIcon)
                Toggle(L("settings.login"), isOn: Binding(get: { startAtLogin }, set: setLogin)).toggleStyle(.checkbox).socle(Socle.T.body)
                hint("settings.menubar.hint")
            }
            block("settings.switcher") {
                hint("settings.switcher.hint")
                if apps.isEmpty { Text(L("settings.switcher.none")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted) }
                ForEach(apps) { app in
                    HStack(spacing: Socle.M.space2) {
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        Text(app.name).socle(Socle.T.body).foregroundStyle(Socle.C.text).socleRowName(app.name)
                        Spacer(minLength: Socle.M.space2)
                        Toggle("", isOn: Binding(get: { !prefs.excludedApps.contains(app.id) }, set: { setIncluded(app.id, $0) }))
                            .toggleStyle(.checkbox).labelsHidden()
                    }
                }
            }
        }
    }

    private func reloadApps() {
        var list = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap { app in app.bundleIdentifier.map { RunningEntry(id: $0, name: app.localizedName ?? $0, icon: app.icon) } }
        for id in prefs.excludedApps where !list.contains(where: { $0.id == id }) {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            list.append(RunningEntry(id: id, name: url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id,
                                     icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }))
        }
        apps = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func setIncluded(_ id: String, _ included: Bool) {
        if included { prefs.excludedApps.removeAll { $0 == id } } else if !prefs.excludedApps.contains(id) { prefs.excludedApps.append(id) }
    }

    private func setLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Déclenchement

    private var trigger: some View {
        SocleModuleGrid(minimum: 380) {
            block("settings.keyboard") {
                row("settings.open") { openRecorder(.open) }
                row("settings.style") {
                    SocleSegmented(options: TriggerStyle.allCases, selection: prefs.style, label: { L("style." + $0.rawValue) }, onSelect: { prefs.style = $0 })
                }
                hint(prefs.style == .hold ? "settings.style.hold.hint" : "settings.style.tap.hint")
            }
            block("settings.mouse") {
                row("settings.mouse.button") {
                    Picker("", selection: $prefs.mouseButton) { ForEach(MouseButtonChoice.allCases, id: \.self) { Text(L("mouse." + $0.rawValue)).tag($0) } }
                        .labelsHidden().frame(width: 190)
                }
                row("settings.mouse.modifier") {
                    Picker("", selection: $prefs.mouseModifier) { ForEach(ModifierChoice.allCases, id: \.self) { Text(L("modifier." + $0.rawValue)).tag($0) } }
                        .labelsHidden().frame(width: 190).disabled(prefs.mouseButton == .off)
                }
                hint("settings.mouse.hint")
            }
            block("settings.modules") {
                ForEach(PieModule.allCases, id: \.self) { module in
                    Toggle(L("module." + module.rawValue), isOn: Binding(get: { prefs.isEnabled(module) }, set: { prefs.setEnabled(module, $0) }))
                        .toggleStyle(.checkbox).socle(Socle.T.body)
                }
                row("settings.start") {
                    Picker("", selection: $prefs.startModule) { ForEach(StartModule.allCases, id: \.self) { Text(L("start." + $0.rawValue)).tag($0) } }
                        .labelsHidden().frame(width: 190)
                }
            }
            block("settings.look") {
                row("settings.size") {
                    HStack(spacing: Socle.M.space2) {
                        Slider(value: $prefs.pieScale, in: 0.7...1.3, step: 0.05).frame(width: 120)
                        Text("\(Int((prefs.pieScale * 100).rounded())) %").socle(Socle.T.body).socleValue().frame(minWidth: 44, alignment: .trailing)
                    }
                }
                toggle("settings.atpointer", $prefs.openAtPointer)
                toggle("settings.showname", $prefs.showName)
                toggle("settings.sound", $prefs.sound)
                toggle("settings.animations", $prefs.animations)
                hint("settings.animations.hint")
            }
            block("settings.modulekeys") {
                ForEach([HotkeyAction.launcher, .switcher, .controller, .music], id: \.self) { action in
                    row("module." + action.rawValue) { openRecorder(action) }
                }
                hint("settings.modulekeys.hint")
            }
        }
    }

    private func openRecorder(_ action: HotkeyAction) -> some View {
        HotkeyRecorder(current: prefs.hotkey(action), requireModifier: true,
                       conflict: { hotkey in
                           HotkeyAction.allCases.first { $0 != action && prefs.hotkey($0) == hotkey }.map { L($0 == .open ? "settings.open" : "module." + $0.rawValue) }
                       },
                       onSet: { prefs.setHotkey(action, $0) },
                       onReset: prefs.hotkeys[action.rawValue] != nil ? { prefs.resetHotkey(action) } : nil)
    }

    // MARK: Préréglages

    private var presets: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L("presets.intro")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            sectionTitle("presets.launcher")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Socle.M.space3)], spacing: Socle.M.space3) {
                ForEach(LauncherPresets.all) { preset in presetCard(preset) }
            }
            if let notice { Text(notice).socle(Socle.T.body).foregroundStyle(Socle.C.success) }
            sectionTitle("presets.trigger")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Socle.M.space3)], spacing: Socle.M.space3) {
                ForEach(TriggerProfiles.all) { profile in profileCard(profile) }
            }
            sectionTitle("presets.controller")
            SocleModuleGrid(minimum: 380) {
                block("presets.controller.title") {
                    Text(L("presets.controller.text", controls.defaults.count - 1)).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(controls.defaults.filter { $0.id != ControlDefaults.genericID }.map(\.name).joined(separator: " · "))
                        .socle(Socle.T.meta).foregroundStyle(Socle.C.accentText).fixedSize(horizontal: false, vertical: true)
                    Button(L("presets.controller.reset")) {
                        for set in controls.allSets where controls.isCustomized(set.id) && controls.isBuiltIn(set.id) { controls.reset(set.id) }
                        notice = L("presets.controller.done")
                    }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
        }
        .confirmationDialog(L("presets.replace.title"), isPresented: Binding(get: { pendingReplace != nil }, set: { if !$0 { pendingReplace = nil } }), presenting: pendingReplace) { preset in
            Button(L("presets.replace")) { applyLauncher(preset, replace: true) }
            Button(L("common.cancel"), role: .cancel) {}
        } message: { _ in Text(L("presets.replace.text", launcher.items.count)) }
    }

    private func reloadFound() {
        var map: [String: [String]] = [:]
        for preset in LauncherPresets.all { map[preset.id] = LauncherPresets.resolve(preset) }
        found = map
    }

    private func presetCard(_ preset: LauncherPreset) -> some View {
        let paths = found[preset.id] ?? []
        return VStack(alignment: .leading, spacing: Socle.M.space3) {
            HStack(spacing: Socle.M.space3) {
                Image(systemName: preset.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Socle.C.textStrong)
                    .frame(width: 34, height: 34).background(Socle.C.control, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("preset." + preset.id)).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong).socleRowName(L("preset." + preset.id))
                    Text(paths.isEmpty ? L("presets.none") : L("presets.found", paths.count)).socle(Socle.T.meta)
                        .foregroundStyle(paths.isEmpty ? Socle.C.textSubtle : Socle.C.accentText).lineLimit(1)
                }
            }
            Text(paths.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }.joined(separator: " · "))
                .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(3).frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
            HStack(spacing: Socle.M.space2) {
                Button(L("presets.replace")) { launcher.items.isEmpty ? applyLauncher(preset, replace: true) : (pendingReplace = preset) }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).disabled(paths.isEmpty)
                Button(L("presets.add")) { applyLauncher(preset, replace: false) }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).disabled(paths.isEmpty)
            }
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface).overlay(Rectangle().stroke(Socle.C.border))
    }

    private func applyLauncher(_ preset: LauncherPreset, replace: Bool) {
        let paths = found[preset.id] ?? []
        let count = replace ? launcher.replaceAll(paths: paths) : launcher.add(paths: paths)
        notice = L(replace ? "presets.replaced" : "presets.added", count, L("preset." + preset.id))
    }

    private func profileCard(_ profile: TriggerProfile) -> some View {
        let on = prefs.currentProfile?.id == profile.id
        return Button { prefs.apply(profile); notice = L("presets.trigger.done", L("profile." + profile.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("profile." + profile.id)).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                    Spacer(minLength: 0)
                    if on { Text(L("presets.active")).socle(Socle.T.meta).foregroundStyle(Socle.C.accentText) }
                }
                Text(L("profile." + profile.id + ".text")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Socle.M.space3).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(on ? Socle.C.surfaceSelected : Socle.C.surface)
            .overlay(Rectangle().stroke(on ? Socle.C.accent : Socle.C.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Lanceur

    private var launcherTab: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            HStack(spacing: Socle.M.space3) {
                Text(L("launcher.hint")).socle(Socle.T.body).foregroundStyle(Socle.C.accentText).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Socle.M.space3)
                Text("\(launcher.items.count) / \(LauncherStore.maxItems)").socle(Socle.T.monoSm).foregroundStyle(Socle.C.textMuted)
                Button(L("launcher.add")) { chooseItems() }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(launcher.items.count >= LauncherStore.maxItems)
            }
            if launcher.items.isEmpty {
                Text(L("launcher.empty.long")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).frame(maxWidth: .infinity, minHeight: 120)
                    .background(Socle.C.bgInset).overlay(Rectangle().stroke(Socle.C.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Socle.M.space3)], spacing: Socle.M.space3) {
                ForEach(launcher.items) { item in launcherCard(item) }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { launcher.add(paths: [url.path]) }
                }
            }
            return true
        }
    }

    private func launcherCard(_ item: LauncherItem) -> some View {
        let kind = item.kind
        return HStack(spacing: Socle.M.space3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 34, height: 34)
                .opacity(kind == .missing ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).socleRowName(item.name)
                Text(L(kind == .app ? "kind.app" : kind == .folder ? "kind.folder" : kind == .file ? "kind.file" : "kind.missing"))
                    .socle(Socle.T.meta).foregroundStyle(kind == .missing ? Socle.C.danger : Socle.C.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                smallButton("chevron.left", help: L("launcher.earlier")) { launcher.move(item.id, by: -1) }
                smallButton("chevron.right", help: L("launcher.later")) { launcher.move(item.id, by: 1) }
                smallButton("xmark", help: L("launcher.remove")) { launcher.remove(item.id) }
            }
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface).overlay(Rectangle().stroke(Socle.C.border))
    }

    private func smallButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Socle.C.textSubtle).frame(width: 22, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private func chooseItems() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK { launcher.add(paths: panel.urls.map(\.path)) }
    }

    // MARK: Contrôleur

    private var controller: some View {
        let sets = controls.allSets
        let current = sets.first { $0.id == selectedSet } ?? controls.generic
        return VStack(alignment: .leading, spacing: Socle.M.space4) {
            SocleModuleGrid(minimum: 380) {
                block("controller.access") {
                    HStack(spacing: Socle.M.space3) {
                        Text(L(trusted ? "controller.access.ok" : "controller.access.no")).socle(Socle.T.body)
                            .foregroundStyle(trusted ? Socle.C.success : Socle.C.warning).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if !trusted {
                            Button(L("controller.access.ask")) { KeySender.requestTrust() }
                                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                        }
                    }
                    hint("controller.access.hint")
                }
                block("controller.set") {
                    row("controller.app") {
                        Picker("", selection: $selectedSet) { ForEach(sets) { Text($0.id == ControlDefaults.genericID ? L("ctl.set.generic") : $0.name).tag($0.id) } }
                            .labelsHidden().frame(width: 200)
                    }
                    HStack(spacing: Socle.M.space2) {
                        Button(L("controller.addapp")) { addApp() }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        if controls.isCustomized(current.id) {
                            Button(L(controls.isBuiltIn(current.id) ? "controller.reset" : "controller.remove")) {
                                controls.reset(current.id)
                                if !controls.isBuiltIn(current.id) { selectedSet = ControlDefaults.genericID }
                            }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        }
                    }
                }
            }
            HStack {
                Text(L("controller.actions", current.actions.count, ControlDefaults.maxActions)).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
                Spacer()
                Button(L("controller.addaction")) { editSet(current) { $0.actions.append(ControlAction(label: "", keyCode: -1, modifiers: 0)) } }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(current.actions.count >= ControlDefaults.maxActions)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Socle.M.space3)], spacing: Socle.M.space3) {
                ForEach(current.actions) { action in
                    VStack(alignment: .leading, spacing: Socle.M.space2) {
                        TextField(L("controller.label.placeholder"), text: Binding(get: { action.label }, set: { new in
                            editSet(current) { set in if let i = set.actions.firstIndex(where: { $0.id == action.id }) { set.actions[i].label = new } }
                        })).socleField()
                        HStack {
                            HotkeyRecorder(current: action.keyCode >= 0 ? action.hotkey : nil, requireModifier: false, conflict: { _ in nil },
                                           onSet: { hotkey in
                                editSet(current) { set in
                                    if let i = set.actions.firstIndex(where: { $0.id == action.id }) {
                                        set.actions[i].keyCode = hotkey?.keyCode ?? -1; set.actions[i].modifiers = hotkey?.modifiers ?? 0
                                    }
                                }
                            }, onReset: nil)
                            Spacer(minLength: 0)
                            smallButton("trash", help: L("controller.deleteaction")) { editSet(current) { $0.actions.removeAll { $0.id == action.id } } }
                        }
                    }
                    .padding(Socle.M.space3).background(Socle.C.surface).overlay(Rectangle().stroke(Socle.C.border))
                }
            }
        }
        .onAppear { trusted = KeySender.trusted }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in trusted = KeySender.trusted }
    }

    private func editSet(_ set: ControlSet, _ change: (inout ControlSet) -> Void) {
        var copy = set
        change(&copy)
        controls.save(copy)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        controls.addApp(bundleID: id, name: name)
        selectedSet = id
    }

    // MARK: Musique

    private var music: some View {
        SocleModuleGrid(minimum: 380) {
            block("settings.player") {
                row("settings.player.choice") {
                    Picker("", selection: $prefs.musicPlayer) { ForEach(MusicPlayer.allCases, id: \.self) { Text(L("player." + $0.rawValue)).tag($0) } }
                        .labelsHidden().frame(width: 190)
                }
                hint("settings.player.hint")
            }
            block("settings.automation") {
                Text(L("settings.automation.text")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
                Button(L("settings.automation.open")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
        }
    }

    // MARK: Mises à jour

    private var updates: some View {
        SocleModuleGrid(minimum: 380) {
            block("settings.updates") {
                toggle("settings.autoupdate", $prefs.autoUpdate)
                Button(L("update.check")) { UpdateEngine.shared.checkNow() }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                Text(L("about.version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
            }
        }
    }

    // MARK: Briques

    private func sectionTitle(_ key: String) -> some View {
        Text(L(key).uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted).padding(.top, Socle.M.space2)
    }

    private func block<C: View>(_ key: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            Text(L(key).uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            VStack(alignment: .leading, spacing: Socle.M.space3) { content() }
                .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
                .background(Socle.C.surface).overlay(Rectangle().stroke(Socle.C.border))
        }
    }

    private func row<C: View>(_ key: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: Socle.M.space3) {
            Text(L(key)).socle(Socle.T.body).foregroundStyle(Socle.C.text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Socle.M.space2)
            control()
        }
        .frame(minHeight: Socle.M.sizeControl)
    }

    private func toggle(_ key: String, _ binding: Binding<Bool>) -> some View {
        Toggle(L(key), isOn: binding).toggleStyle(.checkbox).socle(Socle.T.body)
    }

    private func hint(_ key: String) -> some View {
        Text(L(key)).socle(Socle.T.meta).foregroundStyle(Socle.C.accentText).fixedSize(horizontal: false, vertical: true)
    }
}

/// Saisie d'un raccourci : Échap annule, ⌫ efface. Les raccourcis globaux sont suspendus pendant la saisie.
struct HotkeyRecorder: View {
    let current: Hotkey?
    var requireModifier = true
    var conflict: (Hotkey) -> String?
    let onSet: (Hotkey?) -> Void
    var onReset: (() -> Void)?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: Socle.M.space2) {
                Button(recording ? L("shortcut.recording") : current.map(KeyName.label) ?? L("shortcut.none")) { recording ? stop() : start() }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).frame(width: 150)
                if let onReset, !recording {
                    Button(L("shortcut.reset")) { onReset() }.buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            if let message { Text(message).socle(Socle.T.meta).foregroundStyle(Socle.C.danger) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil; recording = true
        HotkeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in handle(event); return nil }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }

    private func handle(_ event: NSEvent) {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if code == 53 { stop(); return }
        if code == 51, flags.isEmpty { stop(); onSet(nil); return }
        if requireModifier, flags.intersection([.command, .option, .control]).isEmpty, !KeyName.isFunctionKey(code) {
            message = L("shortcut.needs.modifier"); return
        }
        let hotkey = Hotkey(keyCode: code, modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection([.command, .option, .control, .shift]).rawValue)
        if let other = conflict(hotkey) { message = L("shortcut.taken.other", other); return }
        stop()
        onSet(hotkey)
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    var launcher: LauncherStore!
    var controls: ControlStore!

    func show(tab: SettingsTab? = nil, quietly: Bool = false) {
        if let tab { SettingsRouter.shared.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = L("settings.title")
            w.contentView = NSHostingView(rootView: SettingsView(launcher: launcher, controls: controls))
            w.socleCenter()
            window = w
        }
        if quietly { window?.orderFront(nil) } else { window?.present() }
    }

    var contentView: NSView? { window?.contentView }
}
