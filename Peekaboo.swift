// Peekaboo — guscio nativo del fantasmino.
//
// Una finestra senza bordi, con sfondo trasparente, sempre sopra le altre,
// trascinabile e ridimensionabile; piu' un'icona nella barra in alto, le
// notifiche di sistema e una scorciatoia globale da tastiera.
// La grafica vera vive nella WKWebView (ui/index.html).
//
// Compila con:  ./build.sh

import AppKit
import Carbon.HIToolbox
import UserNotifications
import WebKit

let PORT = ProcessInfo.processInfo.environment["PEEKABOO_PORT"] ?? "8787"
let BASE = "http://127.0.0.1:\(PORT)"

let MIN_SIZE = NSSize(width: 260, height: 220)
let HOTKEY_ID: UInt32 = 1

// MARK: - Finestra

/// Senza questo una finestra .borderless non riceve mai i click.
final class GhostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler,
                 NSMenuDelegate, UNUserNotificationCenterDelegate {

    var window: GhostWindow!
    var web: WKWebView!
    var status: NSStatusItem!

    // trascinamento e ridimensionamento manuali: la WKWebView si mangia
    // gli eventi nativi, quindi li pilota la JS e li eseguiamo qui
    private enum Grab { case none, move, resize }
    private var grab = Grab.none
    private var grabMouse = NSPoint.zero
    private var grabFrame = NSRect.zero

    private var snapshot: [String: Any] = [:]
    private var settings: [String: Any] = [:]
    private var lastStates: [Int: String] = [:]     // pid -> stato precedente
    private var lastForgottenNote = Date.distantPast
    private var notificationsReady = false
    private var firstPoll = true

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
        installHotkey()
        askNotificationPermission()
        poll()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    // MARK: finestra

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "app")

        let saved = UserDefaults.standard.string(forKey: "frame")
        let frame = saved.map(NSRectFromString) ?? defaultFrame()

        web = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")      // sfondo trasparente
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        web.autoresizingMask = [.width, .height]
        web.load(URLRequest(url: URL(string: BASE)!))

        window = GhostWindow(contentRect: frame,
                             styleMask: [.borderless, .resizable],
                             backing: .buffered,
                             defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.minSize = MIN_SIZE
        window.setFrame(clamp(frame), display: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func defaultFrame() -> NSRect {
        let vis = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 340, height: min(580, vis.height - 48))
        return NSRect(x: vis.maxX - size.width - 24, y: vis.minY + 24,
                      width: size.width, height: size.height)
    }

    /// Tiene la finestra dentro lo schermo e mai piu' alta del desktop utile.
    private func clamp(_ f: NSRect) -> NSRect {
        guard let vis = (window?.screen ?? NSScreen.main)?.visibleFrame else { return f }
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

    /// Espande la finestra a tutta l'altezza utile dello schermo.
    private func fullHeight() {
        guard let vis = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let isTall = window.frame.height >= vis.height - 4
        var r = window.frame
        if isTall {                                  // gia' alta: torna a misura comoda
            r.size.height = min(580, vis.height - 48)
            r.origin.y = vis.minY + 24
        } else {
            r.size.height = vis.height
            r.origin.y = vis.minY
        }
        window.setFrame(clamp(r), display: true, animate: true)
        saveFrame()
    }

    /// La JS segnala l'inizio del gesto, qui seguiamo il mouse.
    private func installGrabMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] ev in
            guard let self, self.grab != .none else { return ev }
            let now = NSEvent.mouseLocation
            let dx = now.x - self.grabMouse.x, dy = now.y - self.grabMouse.y
            var r = self.grabFrame

            switch self.grab {
            case .move:
                r.origin = NSPoint(x: r.origin.x + dx, y: r.origin.y + dy)
            case .resize:
                // maniglia in basso a destra: il bordo alto resta fermo
                r.size.width = max(MIN_SIZE.width, r.width + dx)
                r.size.height = max(MIN_SIZE.height, r.height - dy)
                r.origin.y = self.grabFrame.maxY - r.height
            case .none:
                break
            }
            self.window.setFrame(self.clamp(r), display: true)
            return ev
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] ev in
            guard let self else { return ev }
            if self.grab != .none { self.saveFrame() }
            self.grab = .none
            return ev
        }
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
        case "fullheight":
            fullHeight()
        case "settings":
            if let s = body["settings"] as? [String: Any] { apply(settings: s) }
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func apply(settings s: [String: Any]) {
        settings = s
        let onTop = s["alwaysOnTop"] as? Bool ?? true
        window.level = onTop ? .floating : .normal
    }

    // MARK: notifiche di sistema

    private func askNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }  // serve un vero .app
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
            DispatchQueue.main.async { self?.notificationsReady = ok }
        }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])     // mostrale anche se Peekaboo e' in primo piano
    }

    private func notify(_ title: String, _ body: String) {
        let sound = (settings["notifications"] as? [String: Any])?["sound"] as? Bool ?? true

        if notificationsReady {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            if sound { c.sound = .default }
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            return
        }
        // Ripiego per l'eseguibile non impacchettato.
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

    /// Confronta lo stato di adesso con quello di prima e avvisa sui cambiamenti.
    private func checkTransitions(_ data: [String: Any]) {
        let dnd = data["dnd"] as? Bool ?? false
        var now: [Int: String] = [:]
        var newlyWaiting: [String] = []
        var newlyReplied: [String] = []

        for g in data["groups"] as? [[String: Any]] ?? [] {
            for s in g["sessions"] as? [[String: Any]] ?? [] {
                guard let pid = s["pid"] as? Int,
                      let state = s["state"] as? String else { continue }
                now[pid] = state
                let before = lastStates[pid]
                guard !firstPoll, before != nil, before != state else { continue }
                let name = s["name"] as? String ?? "una sessione"
                if state == "waiting" { newlyWaiting.append(name) }
                if state == "replied" && before == "working" { newlyReplied.append(name) }
            }
        }
        lastStates = now
        defer { firstPoll = false }
        guard !dnd, !firstPoll else { return }

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
        // Le dimenticate sono una condizione, non un evento: al massimo una volta al giorno.
        let forgotten = data["forgotten"] as? Int ?? 0
        if wants("forgotten"), forgotten > 2,
           Date().timeIntervalSince(lastForgottenNote) > 86_400 {
            lastForgottenNote = Date()
            notify("Sessioni dimenticate",
                   "\(forgotten) sessioni ferme da un pezzo. Vuoi chiuderle?")
        }
    }

    // MARK: barra in alto

    private func buildStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "👻"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
    }

    private func poll() {
        guard let url = URL(string: "\(BASE)/api/sessions") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] d, _, _ in
            guard let self, let d,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { return }
            DispatchQueue.main.async {
                self.snapshot = j
                if let s = j["settings"] as? [String: Any] { self.apply(settings: s) }
                self.checkTransitions(j)

                let c = j["counts"] as? [String: Int] ?? [:]
                let waiting = c["waiting"] ?? 0, working = c["working"] ?? 0
                if waiting > 0        { self.status.button?.title = "👻 \(waiting)❗️" }
                else if working > 0   { self.status.button?.title = "👻 \(working)" }
                else                  { self.status.button?.title = "👻" }
            }
        }.resume()
    }

    private static let colors: [String: NSColor] = [
        "working":  NSColor(red: 0.24, green: 0.86, blue: 0.59, alpha: 1),
        "waiting":  NSColor(red: 1.00, green: 0.71, blue: 0.28, alpha: 1),
        "replied":  NSColor(red: 0.37, green: 0.70, blue: 1.00, alpha: 1),
        "sleeping": NSColor(red: 0.49, green: 0.53, blue: 0.59, alpha: 1),
    ]

    /// Un fantasmino minuscolo del colore dello stato, per il menu.
    private func ghostDot(_ state: String) -> NSImage {
        let size = NSSize(width: 11, height: 12)
        let img = NSImage(size: size)
        img.lockFocus()
        (App.colors[state] ?? .gray).setFill()
        let p = NSBezierPath()
        p.appendArc(withCenter: NSPoint(x: 5.5, y: 7), radius: 4.6,
                    startAngle: 0, endAngle: 180)
        p.line(to: NSPoint(x: 0.9, y: 2.4))
        p.line(to: NSPoint(x: 2.8, y: 3.8))
        p.line(to: NSPoint(x: 4.6, y: 2.4))
        p.line(to: NSPoint(x: 6.4, y: 3.8))
        p.line(to: NSPoint(x: 8.2, y: 2.4))
        p.line(to: NSPoint(x: 10.1, y: 3.8))
        p.close()
        p.fill()
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
        let id = EventHotKeyID(signature: OSType(0x504B4142), id: HOTKEY_ID)  // 'PKAB'
        RegisterEventHotKey(UInt32(kVK_ANSI_G),
                            UInt32(cmdKey | optionKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
