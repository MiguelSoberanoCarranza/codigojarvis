import Cocoa
import SwiftUI

@main
class TestAppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a regular app so it shows up in Dock and has focus
        NSApp.setActivationPolicy(.regular)
        
        let frame = NSRect(x: 300, y: 300, width: 400, height: 300)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Test App JarvisNotch"
        
        let view = Color.red
            .overlay(
                Text("Si ves esto, el servidor de ventanas funciona!")
                    .font(.headline)
                    .foregroundColor(.white)
            )
        window.contentView = NSHostingView(rootView: view)
        
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // Force app to activate and bring window to front
        NSApp.activate(ignoringOtherApps: true)
        print("[TestApp] Window successfully ordered front!")
    }
}
