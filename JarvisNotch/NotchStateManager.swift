import Foundation
import AppKit
import SwiftUI

class NotchStateManager: ObservableObject {
    weak var window: NSWindow?
    
    // UI state: controls SwiftUI transitions and visibility of widgets
    @Published var isExpanded: Bool = false {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let window = self.window else { return }
                window.ignoresMouseEvents = !self.isExpanded
            }
        }
    }
    
    // Dimensions
    let collapsedWidth: CGFloat = 318
    var collapsedHeight: CGFloat = 38.7
    
    let expandedWidth: CGFloat = 450
    let expandedHeight: CGFloat = 320
    
    private var mousePollTimer: Timer?
    
    init() {}
    
    deinit {
        mousePollTimer?.invalidate()
    }
    
    func setup(for window: NSWindow) {
        self.window = window
        window.ignoresMouseEvents = true // Start collapsed: pass all clicks through!
        adjustCollapsedHeight()
        updateWindowFrame()
        startMousePolling()
    }
    
    private func adjustCollapsedHeight() {
        guard let window = window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let s = screen else { return }
        
        if #available(macOS 12.0, *) {
            let topInset = s.safeAreaInsets.top
            if topInset > 0 {
                self.collapsedHeight = topInset + 0.7
            } else {
                self.collapsedHeight = 24
            }
        } else {
            self.collapsedHeight = 24
        }
    }
    
    func updateWindowFrame() {
        guard let window = window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let s = screen else { return }
        
        let screenFrame = s.frame
        let topY = screenFrame.origin.y + screenFrame.size.height
        
        // Window size is ALWAYS static (expandedWidth and expandedHeight)
        let targetRect = NSRect(
            x: screenFrame.origin.x + (screenFrame.size.width - expandedWidth) / 2,
            y: topY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )
        
        logToFile("[JarvisNotch] Initialized Static Frame: \(targetRect)")
        
        DispatchQueue.main.async {
            window.setFrame(targetRect, display: true, animate: false)
        }
    }
    
    private func startMousePolling() {
        mousePollTimer?.invalidate()
        mousePollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }
    
    private func checkMousePosition() {
        guard let window = window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let s = screen else { return }
        
        let screenFrame = s.frame
        let mouseLoc = NSEvent.mouseLocation // Global screen coordinates (Y=0 is bottom)
        
        let screenWidth = screenFrame.size.width
        let screenHeight = screenFrame.origin.y + screenFrame.size.height
        
        // 1. Collapsed notch active area
        let notchWidth = collapsedWidth
        let notchHeight = collapsedHeight
        let notchRect = NSRect(
            x: screenFrame.origin.x + (screenWidth - notchWidth) / 2,
            y: screenHeight - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        // 2. Expanded dashboard active area
        let expandedW = expandedWidth
        let expandedH = expandedHeight
        let expandedRect = NSRect(
            x: screenFrame.origin.x + (screenWidth - expandedW) / 2,
            y: screenHeight - expandedH,
            width: expandedW,
            height: expandedH
        )
        
        // Expand spring has subtle bounce; collapse spring is critically damped (no height undershoot!)
        let expandSpring = Animation.spring(response: 0.36, dampingFraction: 0.72, blendDuration: 0)
        let collapseSpring = Animation.spring(response: 0.30, dampingFraction: 0.98, blendDuration: 0)
        
        // Decide state transitions based on coordinates
        if isExpanded {
            if !expandedRect.contains(mouseLoc) {
                logToFile("[NotchStateManager] Mouse left expanded bounds")
                withAnimation(collapseSpring) {
                    isExpanded = false
                }
            }
        } else {
            if notchRect.contains(mouseLoc) {
                logToFile("[NotchStateManager] Mouse entered notch bounds")
                withAnimation(expandSpring) {
                    isExpanded = true
                }
            }
        }
    }
    
    func logToFile(_ message: String) {
        let logPath = "/Users/miguelsoberano/codigojarvis/JarvisNotch/log.txt"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let logLine = "[\(timestamp)] \(message)\n"
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try? logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
