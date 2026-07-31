// Companion — guscio nativo del fantasmino.
//
// Una finestra senza bordi, con sfondo trasparente, sempre sopra le altre e
// trascinabile ovunque; piu' un'icona nella barra in alto con l'elenco delle
// sessioni. La grafica vera vive nella WKWebView (ui/index.html).
//
// Compila con:  swiftc -O Ghost.swift -o companion-app

import AppKit
import WebKit

let PORT = ProcessInfo.processInfo.environment["COMPANION_PORT"] ?? "8787"
let BASE = "http://127.0.0.1:\(PORT)"

// MARK: - Finestra

/// Senza questo una finestra .borderless non riceve mai i click.
final class GhostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, NSMenuDelegate {

    var window: GhostWindow!
    var web: WKWebView!
    var status: NSStatusItem!

    // stato del trascinamento manuale (la WKWebView si mangia i drag nativi)
    private var dragging = false
    private var dragMouse = NSPoint.zero
    private var dragOrigin = NSPoint.zero

    private var snapshot: [String: Any] = [:]

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // niente icona nel Dock
        buildWindow()
        buildStatusItem()
        installDragMonitors()
        pollForMenu()
    }

    // MARK: finestra flottante

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "app")

        let frame = NSRect(x: 0, y: 0, width: 340, height: 580)
        web = WKWebView(frame: frame, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")   // sfondo trasparente
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        web.load(URLRequest(url: URL(string: BASE)!))

        window = GhostWindow(contentRect: frame,
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating                 // sempre sopra le altre app
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = web
        window.isReleasedWhenClosed = false

        // in basso a destra, con un po' di margine
        if let vis = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: vis.maxX - frame.width - 24,
                                          y: vis.minY + 24))
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Trascinamento: la JS segnala l'inizio, qui seguiamo il mouse.
    private func installDragMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] ev in
            guard let self, self.dragging else { return ev }
            let now = NSEvent.mouseLocation
            self.window.setFrameOrigin(NSPoint(
                x: self.dragOrigin.x + (now.x - self.dragMouse.x),
                y: self.dragOrigin.y + (now.y - self.dragMouse.y)))
            return ev
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] ev in
            self?.dragging = false
            return ev
        }
    }

    func userContentController(_ c: WKUserContentController,
                               didReceive msg: WKScriptMessage) {
        guard let body = msg.body as? [String: Any],
              let kind = body["type"] as? String else { return }
        switch kind {
        case "dragstart":
            dragging = true
            dragMouse = NSEvent.mouseLocation
            dragOrigin = window.frame.origin
        case "quit":
            NSApp.terminate(nil)
        default:
            break
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

    /// Aggiorna il titolino nella barra ogni pochi secondi.
    private func pollForMenu() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.fetch { data in
                self?.snapshot = data
                let c = data["counts"] as? [String: Int] ?? [:]
                let waiting = c["waiting"] ?? 0
                let working = c["working"] ?? 0
                var label = "👻"
                if waiting > 0      { label = "👻 \(waiting)❗️" }
                else if working > 0 { label = "👻 \(working)" }
                self?.status.button?.title = label
            }
        }
    }

    private func fetch(_ done: @escaping ([String: Any]) -> Void) {
        guard let url = URL(string: "\(BASE)/api/sessions") else { return }
        URLSession.shared.dataTask(with: url) { d, _, _ in
            guard let d,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { return }
            DispatchQueue.main.async { done(j) }
        }.resume()
    }

    private static let colors: [String: NSColor] = [
        "working":  NSColor(red: 0.24, green: 0.86, blue: 0.59, alpha: 1),
        "waiting":  NSColor(red: 1.00, green: 0.71, blue: 0.28, alpha: 1),
        "replied":  NSColor(red: 0.37, green: 0.70, blue: 1.00, alpha: 1),
        "sleeping": NSColor(red: 0.49, green: 0.53, blue: 0.59, alpha: 1),
    ]

    private func dot(_ state: String) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let img = NSImage(size: size)
        img.lockFocus()
        (App.colors[state] ?? .gray).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        return img
    }

    /// Il menu si ricostruisce a ogni apertura, cosi' e' sempre fresco.
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
            let header = NSMenuItem(
                title: crowded ? "\(name) — \(awake) sveglie, troppe" : name,
                action: nil, keyEquivalent: "")
            header.attributedTitle = NSAttributedString(
                string: header.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: crowded
                        ? NSColor(red: 1, green: 0.42, blue: 0.54, alpha: 1)
                        : NSColor.secondaryLabelColor,
                ])
            menu.addItem(header)

            for s in g["sessions"] as? [[String: Any]] ?? [] {
                let state = s["state"] as? String ?? "sleeping"
                let item = NSMenuItem(title: "   " + (s["name"] as? String ?? "?"),
                                      action: #selector(focusSession(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.image = dot(state)
                item.representedObject = s["pid"]
                item.toolTip = s["activity"] as? String
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let toggle = NSMenuItem(title: window.isVisible ? "Nascondi il fantasmino"
                                                        : "Mostra il fantasmino",
                                action: #selector(toggleWindow), keyEquivalent: "g")
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

    @objc private func toggleWindow() {
        if window.isVisible { window.orderOut(nil) }
        else { window.makeKeyAndOrderFront(nil) }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
