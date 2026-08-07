import Cocoa

// Retain a strong global reference to AppDelegate so ARC does not deallocate it
let strongDelegate = AppDelegate()

let app = NSApplication.shared
app.delegate = strongDelegate
app.run()
