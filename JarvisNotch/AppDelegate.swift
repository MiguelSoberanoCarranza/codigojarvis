import Cocoa
import SwiftUI

class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    var stateManager: NotchStateManager
    
    init(rootView: Content, stateManager: NotchStateManager) {
        self.stateManager = stateManager
        super.init(rootView: rootView)
    }
    
    @objc required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @MainActor required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let height = self.bounds.height
        
        if stateManager.isExpanded {
            // In expanded mode, the entire 450x320 area intercepts clicks
            return super.hitTest(point)
        } else {
            // Collapsed: Click hits only the Left Wing or Right Wing
            // Window is 450x320. Left wing and Right wing are centered (total width 318)
            // Margins: (450 - 318)/2 = 66.
            // Left wing: X [66, 146]. Right wing: X [304, 384].
            // Y is at the top of the window: [height - collapsedHeight, height].
            let leftWingRect = NSRect(x: 66, y: height - stateManager.collapsedHeight, width: 80, height: stateManager.collapsedHeight)
            let rightWingRect = NSRect(x: 304, y: height - stateManager.collapsedHeight, width: 80, height: stateManager.collapsedHeight)
            
            if leftWingRect.contains(point) || rightWingRect.contains(point) {
                return super.hitTest(point)
            }
            return nil
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NotchWindow!
    var stateManager: NotchStateManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let startupLog = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium))] [AppDelegate] entered! Screens count: \(NSScreen.screens.count)\n"
        try? startupLog.write(toFile: "/Users/miguelsoberano/codigojarvis/JarvisNotch/log.txt", atomically: true, encoding: .utf8)
        
        // Run as background agent
        NSApp.setActivationPolicy(.accessory)
        
        stateManager = NotchStateManager()
        
        // Static frame: 450x320 centered at the top of the screen
        let screen = NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1710, height: 1112)
        let topY = screenFrame.origin.y + screenFrame.size.height
        
        let windowFrame = NSRect(
            x: screenFrame.origin.x + (screenFrame.size.width - 450) / 2,
            y: topY - 320,
            width: 450,
            height: 320
        )
        
        window = NotchWindow(contentRect: windowFrame)
        
        let contentView = ContentView(stateManager: stateManager)
        let hostingView = InteractiveHostingView(rootView: contentView, stateManager: stateManager)
        window.contentView = hostingView
        
        stateManager.setup(for: window)
        
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
