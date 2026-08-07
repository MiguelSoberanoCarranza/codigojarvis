import Cocoa

class NotchWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        
        // Ensure the window floats on top of everything (even the menu bar)
        self.level = .screenSaver
        
        // stationary: stays in place during mission control
        // canJoinAllSpaces: stays visible when switching virtual desktops
        // ignoresCycle: doesn't get activated with Command+Tab
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        // Allow mouse clicks to interact with our UI
        self.ignoresMouseEvents = false
        
        // Hide standard window features
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovable = false
        self.acceptsMouseMovedEvents = true
    }
    
    // Crucial for borderless windows: allow them to receive keyboard focus (e.g. for widgets, forms, search)
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}
