import Cocoa
import WebKit

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class Controller: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var windows: [NSWindow] = []
    var views: [WKWebView] = []
    var status: NSStatusItem!
    var paused = false
    var computerSleeping = false
    var displaySleeping = false
    var sleeping: Bool { computerSleeping || displaySleeping }
    var speed = 12
    var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "light"
    var appearanceItems: [NSMenuItem] = []
    var timer: Timer?
    var pending = Set<ObjectIdentifier>()
    var diagnosticTick = 0
    var screenLayout = ""
    func diagnostic(_ message: String) {
        guard let path = ProcessInfo.processInfo.environment["GROUNDSURF_DIAGNOSTICS"], let handle = FileHandle(forWritingAtPath:path) else { return }
        handle.seekToEndOfFile(); handle.write(Data("\(Date().timeIntervalSince1970) event=\(message)\n".utf8)); try? handle.close()
    }
    var pauseItem: NSMenuItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let iconURL = Bundle.main.url(forResource:"GroundSurf",withExtension:"icns"), let icon = NSImage(contentsOf:iconURL) { NSApp.applicationIconImage = icon }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "GroundSurf"
        status.button?.toolTip = "GroundSurf"
        let menu = NSMenu()
        let title = NSMenuItem(title: "GroundSurf", action: nil, keyEquivalent: "")
        menu.addItem(title)
        pauseItem = item("Pause", #selector(togglePause), menu)
        let speeds = NSMenu()
        for (name, value) in [("Slow",6),("Gentle",12),("Brisk",24)] {
            let entry = item(name, #selector(setSpeed(_:)), speeds)
            entry.tag = value
            entry.state = value == speed ? .on : .off
        }
        let speedMenu = NSMenuItem(title:"Scroll Speed",action:nil,keyEquivalent:"")
        speedMenu.submenu = speeds; menu.addItem(speedMenu)
        let appearances = NSMenu()
        if !["light","dark","purple","system"].contains(appearance) {appearance="light"}
        for (name, value) in [("Light","light"),("Dark","dark"),("Dark Purple","purple"),("Follow System","system")] {
            let entry = item(name, #selector(setAppearance(_:)), appearances)
            entry.representedObject=value;entry.state=value == appearance ? .on : .off
            appearanceItems.append(entry)
        }
        let appearanceMenu = NSMenuItem(title:"Appearance",action:nil,keyEquivalent:"")
        appearanceMenu.submenu=appearances;menu.addItem(appearanceMenu)
        item("New Landscape", #selector(newLandscape), menu)
        menu.addItem(.separator())
        item("About GroundSurf", #selector(about), menu)
        item("Quit", #selector(quit), menu)
        status.menu = menu
        NotificationCenter.default.addObserver(self, selector:#selector(rebuild), name:NSApplication.didChangeScreenParametersNotification, object:nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector:#selector(computerSleep), name:NSWorkspace.willSleepNotification, object:nil)
        center.addObserver(self, selector:#selector(displaySleep), name:NSWorkspace.screensDidSleepNotification, object:nil)
        center.addObserver(self, selector:#selector(computerWake), name:NSWorkspace.didWakeNotification, object:nil)
        center.addObserver(self, selector:#selector(displayWake), name:NSWorkspace.screensDidWakeNotification, object:nil)
        rebuild()
        updateTimer()
    }
    func updateTimer() {
        timer?.invalidate();timer=nil
        guard !paused, !sleeping else {return}
        let nextTimer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.paused, !self.sleeping else { return }
            for view in self.views {
                let id = ObjectIdentifier(view)
                guard !self.pending.contains(id) else { continue }
                self.pending.insert(id)
                view.evaluateJavaScript("window.wallpaper?.tick()") { [weak self] _, _ in self?.pending.remove(id) }
            }
            self.diagnosticTick += 1
            if self.diagnosticTick % 150 == 0, let path = ProcessInfo.processInfo.environment["GROUNDSURF_DIAGNOSTICS"] {
                for (index,view) in self.views.enumerated() {
                    view.evaluateJavaScript("JSON.stringify(window.wallpaper?.stats())") { value, error in
                        let line = "\(Date().timeIntervalSince1970) screen=\(index) \(value ?? String(describing:error))\n"
                        if let handle = FileHandle(forWritingAtPath:path) { handle.seekToEndOfFile();handle.write(Data(line.utf8));try? handle.close() }
                    }
                }
            }
        }
        timer=nextTimer
        RunLoop.main.add(nextTimer, forMode:.common)
    }
    @discardableResult func item(_ name:String,_ action:Selector,_ menu:NSMenu)->NSMenuItem {
        let entry=NSMenuItem(title:name,action:action,keyEquivalent:"");entry.target=self;menu.addItem(entry);return entry
    }
    @objc func rebuild() {
        let layout = NSScreen.screens.map { "\($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown"):\($0.frame):\($0.backingScaleFactor)" }.joined(separator:";")
        guard windows.isEmpty || layout != screenLayout else { return }
        screenLayout = layout
        diagnostic("display-layout-rebuild")
        for view in views {view.stopLoading()}
        for window in windows {window.close()}
        windows=[]; views=[]; pending.removeAll()
        for screen in NSScreen.screens {
            let window=DesktopWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            window.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopWindow))+1)
            window.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
            window.ignoresMouseEvents=true;window.backgroundColor=NSColor(calibratedRed:0.96,green:0.93,blue:0.85,alpha:1)
            let view=WKWebView(frame:NSRect(origin:.zero,size:screen.frame.size))
            view.navigationDelegate=self;window.contentView=view
            windows.append(window);views.append(view)
            load(view);window.orderFrontRegardless()
        }
    }
    func load(_ view:WKWebView) {
        guard let url=Bundle.main.url(forResource:"landscape",withExtension:"html") else {return}
        view.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {apply()}
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { diagnostic("web-content-terminated-reloading"); load(webView) }
    func apply(){for view in views {view.evaluateJavaScript("window.wallpaper?.appearance('\(appearance)');window.wallpaper?.pause(\(paused || sleeping));window.wallpaper?.speed(\(speed))",completionHandler:nil)}}
    @objc func togglePause(){paused.toggle();pauseItem.title=paused ? "Resume" : "Pause";apply();updateTimer()}
    @objc func setSpeed(_ sender:NSMenuItem){speed=sender.tag;for entry in sender.menu!.items {entry.state=entry===sender ? .on : .off};apply()}
    @objc func setAppearance(_ sender:NSMenuItem){
        guard let value=sender.representedObject as? String else {return}
        appearance=value;UserDefaults.standard.set(value,forKey:"appearance")
        for entry in appearanceItems {entry.state=entry===sender ? .on : .off}
        apply()
    }
    @objc func newLandscape(){diagnostic("new-landscape");for view in views{load(view)}}
    @objc func computerSleep(){computerSleeping=true;apply();updateTimer()}
    @objc func displaySleep(){displaySleeping=true;apply();updateTimer()}
    @objc func computerWake(){computerSleeping=false;apply();updateTimer()}
    @objc func displayWake(){displaySleeping=false;apply();updateTimer()}
    @objc func about(){NSApp.activate(ignoringOtherApps:true);let alert=NSAlert();alert.icon=NSApp.applicationIconImage;alert.messageText="GroundSurf";alert.informativeText="GroundSurf by Akhilesh Khajuria\n\nEndlessly generated Chinese landscapes.\nOriginal artwork generator: Lingdong Huang (MIT license).\nOffline desktop adaptation. Use the GroundSurf menu to pause or quit.";alert.runModal()}
    @objc func quit(){NSApp.terminate(nil)}
}
let app=NSApplication.shared
let controller=Controller()
app.delegate=controller
app.run()
