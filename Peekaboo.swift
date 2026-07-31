// Peekaboo — guscio nativo del fantasmino.
//
// Una finestra senza bordi e trasparente, sempre sopra le altre, che puo'
// occupare una colonna dello schermo che scegli tu; piu' l'icona nella barra,
// le notifiche di sistema, la scorciatoia globale, gli occhi che seguono il
// mouse e il rilevamento di microfono e telecamera.
// La grafica vera vive nella WKWebView (ui/index.html).
//
// Compila con:  ./build.sh

import AppKit
import Carbon.HIToolbox
import CoreAudio
import CoreMediaIO
import UserNotifications
import WebKit

let PORT = ProcessInfo.processInfo.environment["PEEKABOO_PORT"] ?? "8787"
let BASE = "http://127.0.0.1:\(PORT)"

let MIN_SIZE = NSSize(width: 240, height: 200)
let HOTKEY_ID: UInt32 = 1

/// Senza questo una finestra .borderless non riceve mai i click.
final class GhostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler,
                 NSMenuDelegate, UNUserNotificationCenterDelegate {

    var window: GhostWindow!
    var web: WKWebView!
    var status: NSStatusItem!

    private enum Grab { case none, move, resize }
    private var grab = Grab.none
    private var grabMouse = NSPoint.zero
    private var grabFrame = NSRect.zero

    private var snapshot: [String: Any] = [:]
    private var settings: [String: Any] = [:]
    private var lastStates: [Int: String] = [:]
    private var lastForgottenNote = Date.distantPast
    private var notificationsReady = false
    private var firstPoll = true

    /// Rettangoli "solidi" comunicati dalla UI, in coordinate CSS.
    /// Servono a far passare i click dove non c'e' niente disegnato.
    private var solidRects: [NSRect] = []
    private var ignoring = false
    private var appIsFront = true
    private var mouseInside = false
    private var lastLook = Date.distantPast

    private var micOn = false, camOn = false

    // MARK: avvio

    func applicationDidFinishLaunching(_ n: Notification) {
        // Un solo fantasmino per volta: con l'avvio automatico e' facile
        // ritrovarsi due istanze (una da launchctl, una lanciata a mano).
        if let id = Bundle.main.bundleIdentifier {
            let mine = NSRunningApplication.current.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0.processIdentifier != mine }
            if !others.isEmpty {
                others.first?.activate(options: [])
                NSApp.terminate(nil)
                return
            }
        }
        NSApp.setActivationPolicy(.accessory)       // niente icona nel Dock
        buildWindow()
        buildStatusItem()
        installGrabMonitors()
        installMouseMonitor()
        installHotkey()
        watchFrontmostApp()
        askNotificationPermission()

        poll()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkDevices() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.applyLayout(); self?.pushScreens()
            }
    }

    // MARK: finestra e disposizione

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "app")

        web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        web.autoresizingMask = [.width, .height]
        web.load(URLRequest(url: URL(string: BASE)!))

        window = GhostWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 600),
                             styleMask: [.borderless, .resizable],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.minSize = MIN_SIZE
        applyLayout()
        window.makeKeyAndOrderFront(nil)
    }

    /// Lo schermo scelto nelle impostazioni (-1 = quello principale).
    private func chosenScreen() -> NSScreen {
        let idx = settings["screen"] as? Int ?? -1
        let all = NSScreen.screens
        if idx >= 0 && idx < all.count { return all[idx] }
        return NSScreen.main ?? all.first!
    }

    /// Colloca la finestra secondo il preset scelto. "libero" lascia fare a te.
    private func applyLayout(save: Bool = false) {
        let layout = settings["layout"] as? String ?? "full"
        let vis = chosenScreen().visibleFrame
        let side = settings["side"] as? String ?? "right"
        let width = min(max(CGFloat(settings["width"] as? Double ?? 340), MIN_SIZE.width),
                        vis.width)

        if layout == "libero" {
            if let s = UserDefaults.standard.string(forKey: "frame") {
                window.setFrame(clamp(NSRectFromString(s)), display: true)
            }
            return
        }

        var r = NSRect(x: side == "right" ? vis.maxX - width : vis.minX,
                       y: vis.minY, width: width, height: vis.height)
        switch layout {
        case "half":                                    // meta' bassa
            r.size.height = vis.height / 2
        case "tophalf":                                 // meta' alta
            r.size.height = vis.height / 2
            r.origin.y = vis.midY
        default: break                                  // "full": tutta l'altezza
        }
        window.setFrame(r, display: true, animate: false)
        if save { saveFrame() }
    }

    private func clamp(_ f: NSRect) -> NSRect {
        let vis = chosenScreen().visibleFrame
        var r = f
        r.size.width = max(MIN_SIZE.width, min(r.width, vis.width))
        r.size.height = max(MIN_SIZE.height, min(r.height, vis.height))
        r.origin.x = min(max(r.minX, vis.minX), vis.maxX - r.width)
        r.origin.y = min(max(r.minY, vis.minY), vis.maxY - r.height)
        return r
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "frame")
    }

    private func installGrabMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] ev in
            guard let self, self.grab != .none else { return ev }
            let now = NSEvent.mouseLocation
            let dx = now.x - self.grabMouse.x, dy = now.y - self.grabMouse.y
            var r = self.grabFrame
            switch self.grab {
            case .move:   r.origin = NSPoint(x: r.origin.x + dx, y: r.origin.y + dy)
            case .resize:
                r.size.width = max(MIN_SIZE.width, r.width + dx)
                r.size.height = max(MIN_SIZE.height, r.height - dy)
                r.origin.y = self.grabFrame.maxY - r.height
            case .none: break
            }
            self.window.setFrame(self.clamp(r), display: true)
            return ev
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] ev in
            guard let self else { return ev }
            if self.grab != .none {
                self.saveFrame()
                // Spostarla a mano significa volerla libera.
                if (self.settings["layout"] as? String ?? "full") != "libero" {
                    self.postSettings(["layout": "libero"])
                }
            }
            self.grab = .none
            return ev
        }
    }

    // MARK: mouse — occhi che seguono, click che attraversano, dissolvenza

    private func installMouseMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.mouseMoved() }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { handler($0) }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { ev in handler(ev); return ev }
    }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        let f = window.frame
        mouseInside = f.contains(p)

        // punto in coordinate CSS (origine in alto a sinistra)
        let cx = p.x - f.minX
        let cy = f.maxY - p.y

        if settings["clickThrough"] as? Bool ?? true {
            let solid = mouseInside && solidRects.contains { $0.contains(NSPoint(x: cx, y: cy)) }
            setIgnoring(!solid)
        } else {
            setIgnoring(false)
        }
        updateAlpha()

        // Gli occhi seguono il mouse anche fuori dalla finestra, ma senza
        // sommergere la WebView di chiamate.
        guard settings["eyesFollow"] as? Bool ?? true,
              Date().timeIntervalSince(lastLook) > 0.05 else { return }
        lastLook = Date()
        web.evaluateJavaScript("window.lookAt&&lookAt(\(Int(cx)),\(Int(cy)))")
    }

    private func setIgnoring(_ v: Bool) {
        guard v != ignoring else { return }
        ignoring = v
        window.ignoresMouseEvents = v
    }

    private func watchFrontmostApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self.appIsFront = app?.processIdentifier == NSRunningApplication.current.processIdentifier
                self.updateAlpha()
            }
    }

    /// Si smaterializza mentre lavori altrove, torna appena ti avvicini.
    private func updateAlpha() {
        let fade = settings["autoFade"] as? Bool ?? true
        let dim = CGFloat(settings["fadeOpacity"] as? Double ?? 0.32)
        let want: CGFloat = (fade && !appIsFront && !mouseInside) ? dim : 1.0
        guard abs(window.alphaValue - want) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            window.animator().alphaValue = want
        }
    }

    // MARK: microfono e telecamera
    //
    // Nessun permesso richiesto: chiediamo al sistema se il dispositivo sta
    // girando "da qualche parte", senza mai aprire un flusso.

    private func micIsOn() -> Bool {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &id) == noErr, id != 0
        else { return false }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private func camIsOn() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                            &addr, 0, nil, &size) == noErr, size > 0
        else { return false }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil,
                                        size, &used, &devices) == noErr else { return false }

        for dev in devices {
            var running: UInt32 = 0
            var rSize = UInt32(MemoryLayout<UInt32>.size)
            var rAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            if CMIOObjectGetPropertyData(dev, &rAddr, 0, nil, rSize, &rSize, &running) == noErr,
               running != 0 { return true }
        }
        return false
    }

    private func checkDevices() {
        let m = micIsOn(), c = camIsOn()
        guard m != micOn || c != camOn else { return }
        micOn = m; camOn = c
        web.evaluateJavaScript("window.setDevices&&setDevices(\(m),\(c))")
    }

    // MARK: messaggi dalla UI

    func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let body = msg.body as? [String: Any],
              let kind = body["type"] as? String else { return }
        switch kind {
        case "dragstart":
            grab = .move; grabMouse = NSEvent.mouseLocation; grabFrame = window.frame
        case "resizestart":
            grab = .resize; grabMouse = NSEvent.mouseLocation; grabFrame = window.frame
        case "settings":
            if let s = body["settings"] as? [String: Any] {
                let oldLayout = settings["layout"] as? String
                let oldScreen = settings["screen"] as? Int
                let oldSide = settings["side"] as? String
                apply(settings: s)
                if s["layout"] as? String != oldLayout || s["screen"] as? Int != oldScreen
                    || s["side"] as? String != oldSide { applyLayout() }
            }
        case "hitrects":
            solidRects = (body["rects"] as? [[String: Double]] ?? []).map {
                NSRect(x: $0["x"] ?? 0, y: $0["y"] ?? 0,
                       width: $0["w"] ?? 0, height: $0["h"] ?? 0)
            }
        case "ready":
            pushScreens()
            web.evaluateJavaScript("window.setDevices&&setDevices(\(micOn),\(camOn))")
        case "hide":
            window.orderOut(nil)
        case "quit":
            NSApp.terminate(nil)
        default: break
        }
    }

    private func apply(settings s: [String: Any]) {
        settings = s
        window.level = (s["alwaysOnTop"] as? Bool ?? true) ? .floating : .normal
        updateAlpha()
    }

    /// Salva un'impostazione passando dal server, cosi' resta l'unica fonte.
    private func postSettings(_ patch: [String: Any]) {
        guard let url = URL(string: "\(BASE)/api/settings") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: patch)
        URLSession.shared.dataTask(with: r).resume()
    }

    /// Manda alla UI l'elenco degli schermi, per il menu a tendina.
    private func pushScreens() {
        let list = NSScreen.screens.enumerated().map { i, s -> [String: Any] in
            let f = s.frame
            return ["i": i,
                    "name": s.localizedName,
                    "size": "\(Int(f.width))×\(Int(f.height))",
                    "main": s == NSScreen.main]
        }
        guard let d = try? JSONSerialization.data(withJSONObject: list),
              let j = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.setScreens&&setScreens(\(j))")
    }

    // MARK: notifiche di sistema

    private func askNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
            DispatchQueue.main.async { self?.notificationsReady = ok }
        }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    private func notify(_ title: String, _ body: String) {
        let sound = (settings["notifications"] as? [String: Any])?["sound"] as? Bool ?? true
        if notificationsReady {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body
            if sound { c.sound = .default }
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            return
        }
        let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "'") }
        let script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
            + (sound ? " sound name \"Submarine\"" : "")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    private func wants(_ key: String) -> Bool {
        (settings["notifications"] as? [String: Any])?[key] as? Bool ?? false
    }

    private func checkTransitions(_ data: [String: Any]) {
        let dnd = data["dnd"] as? Bool ?? false
        var now: [Int: String] = [:]
        var newlyWaiting: [String] = [], newlyReplied: [String] = []

        for g in data["groups"] as? [[String: Any]] ?? [] {
            for s in g["sessions"] as? [[String: Any]] ?? [] {
                guard let pid = s["pid"] as? Int, let state = s["state"] as? String else { continue }
                now[pid] = state
                let before = lastStates[pid]
                guard !firstPoll, before != nil, before != state else { continue }
                let name = s["name"] as? String ?? "una sessione"
                if state == "waiting" { newlyWaiting.append(name) }
                if state == "replied" && before == "working" { newlyReplied.append(name) }
            }
        }
        lastStates = now
        let wasFirst = firstPoll
        firstPoll = false
        guard !dnd, !wasFirst else { return }

        if wants("waiting"), !newlyWaiting.isEmpty {
            notify(newlyWaiting.count == 1 ? "Una sessione ti aspetta"
                                           : "\(newlyWaiting.count) sessioni ti aspettano",
                   newlyWaiting.prefix(3).joined(separator: ", "))
        }
        if wants("replied"), !newlyReplied.isEmpty {
            notify(newlyReplied.count == 1 ? "Una sessione ha risposto"
                                           : "\(newlyReplied.count) sessioni hanno risposto",
                   newlyReplied.prefix(3).joined(separator: ", "))
        }
        let forgotten = data["forgotten"] as? Int ?? 0
        if wants("forgotten"), forgotten > 2,
           Date().timeIntervalSince(lastForgottenNote) > 86_400 {
            lastForgottenNote = Date()
            notify("Sessioni dimenticate", "\(forgotten) sessioni ferme da un pezzo. Vuoi chiuderle?")
        }
    }

    // MARK: barra in alto

    private func buildStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "👻"
        let menu = NSMenu(); menu.delegate = self
        status.menu = menu
    }

    private func poll() {
        guard let url = URL(string: "\(BASE)/api/sessions") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] d, _, _ in
            guard let self, let d,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            DispatchQueue.main.async {
                self.snapshot = j
                if let s = j["settings"] as? [String: Any] {
                    let first = self.settings.isEmpty
                    self.apply(settings: s)
                    if first { self.applyLayout() }
                }
                self.checkTransitions(j)
                let c = j["counts"] as? [String: Int] ?? [:]
                let waiting = c["waiting"] ?? 0, working = c["working"] ?? 0
                if waiting > 0      { self.status.button?.title = "👻 \(waiting)❗️" }
                else if working > 0 { self.status.button?.title = "👻 \(working)" }
                else                { self.status.button?.title = "👻" }
            }
        }.resume()
    }

    private static let colors: [String: NSColor] = [
        "working":  NSColor(red: 0.24, green: 0.86, blue: 0.59, alpha: 1),
        "waiting":  NSColor(red: 1.00, green: 0.71, blue: 0.28, alpha: 1),
        "replied":  NSColor(red: 0.37, green: 0.70, blue: 1.00, alpha: 1),
        "sleeping": NSColor(red: 0.49, green: 0.53, blue: 0.59, alpha: 1),
    ]

    private func ghostDot(_ state: String) -> NSImage {
        let size = NSSize(width: 11, height: 12)
        let img = NSImage(size: size)
        img.lockFocus()
        (App.colors[state] ?? .gray).setFill()
        let p = NSBezierPath()
        p.appendArc(withCenter: NSPoint(x: 5.5, y: 7), radius: 4.6, startAngle: 0, endAngle: 180)
        p.line(to: NSPoint(x: 0.9, y: 2.4)); p.line(to: NSPoint(x: 2.8, y: 3.8))
        p.line(to: NSPoint(x: 4.6, y: 2.4)); p.line(to: NSPoint(x: 6.4, y: 3.8))
        p.line(to: NSPoint(x: 8.2, y: 2.4)); p.line(to: NSPoint(x: 10.1, y: 3.8))
        p.close(); p.fill()
        img.unlockFocus()
        return img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let groups = snapshot["groups"] as? [[String: Any]] ?? []
        if groups.isEmpty {
            menu.addItem(withTitle: "Nessuna sessione attiva", action: nil, keyEquivalent: "")
        }
        for g in groups {
            let name = g["project"] as? String ?? "?"
            let awake = g["awake"] as? Int ?? 0
            let crowded = g["crowded"] as? Bool ?? false
            let header = NSMenuItem(title: crowded ? "\(name) — \(awake) sveglie, troppe" : name,
                                    action: nil, keyEquivalent: "")
            header.attributedTitle = NSAttributedString(string: header.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: crowded ? NSColor(red: 1, green: 0.42, blue: 0.54, alpha: 1)
                                          : NSColor.secondaryLabelColor])
            menu.addItem(header)
            for s in g["sessions"] as? [[String: Any]] ?? [] {
                let state = s["state"] as? String ?? "sleeping"
                let forgotten = s["forgotten"] as? Bool ?? false
                let item = NSMenuItem(title: "   " + (s["name"] as? String ?? "?")
                                        + (forgotten ? " ·" : ""),
                                      action: #selector(focusSession(_:)), keyEquivalent: "")
                item.target = self
                item.image = ghostDot(state)
                item.representedObject = s["pid"]
                item.toolTip = s["activity"] as? String
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let toggle = NSMenuItem(title: window.isVisible ? "Nascondi il fantasmino"
                                                       : "Mostra il fantasmino",
                                action: #selector(toggleWindow), keyEquivalent: "g")
        toggle.keyEquivalentModifierMask = [.command, .option]
        toggle.target = self
        menu.addItem(toggle)
        let quit = NSMenuItem(title: "Esci", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func focusSession(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int,
              let url = URL(string: "\(BASE)/api/focus") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["pid": pid])
        URLSession.shared.dataTask(with: r).resume()
    }

    @objc func toggleWindow() {
        if window.isVisible { window.orderOut(nil) }
        else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: scorciatoia globale (⌥⌘G)

    private func installHotkey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if hk.id == HOTKEY_ID {
                DispatchQueue.main.async { (NSApp.delegate as? App)?.toggleWindow() }
            }
            return noErr
        }, 1, &spec, nil, nil)

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x504B4142), id: HOTKEY_ID)   // 'PKAB'
        RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(cmdKey | optionKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
