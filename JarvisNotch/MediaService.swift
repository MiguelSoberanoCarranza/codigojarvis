import Foundation
import AppKit

class MediaService: ObservableObject {
    @Published var currentTitle: String = "No Reproduciendo"
    @Published var currentArtist: String = ""
    @Published var isPlaying: Bool = false
    @Published var sourceApp: String = ""
    @Published var albumArtworkImage: NSImage? = nil
    @Published var elapsedTime: Double = 0
    @Published var duration: Double = 0
    
    private var timer: Timer?
    private var lastFetchedTrack: String = ""
    private var emptyTicksCount: Int = 0
    private var mediaRemoteHandle: UnsafeMutableRawPointer? = nil
    private var appleScriptBusy = false
    private var lastAppleScriptAt: Date = .distantPast
    
    // MediaRemote callbacks are Objective-C blocks — @convention(block) is required
    // or the completion never runs / always looks empty.
    private typealias MRGetNowPlayingInfoFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) ([AnyHashable: Any]?) -> Void
    ) -> Void
    private typealias MRRegisterForNowPlayingNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias MRSendCommandFn = @convention(c) (Int32, AnyObject?) -> Bool
    private typealias MRGetNowPlayingApplicationIsPlayingFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Bool) -> Void
    ) -> Void
    
    private var getNowPlayingInfoFn: MRGetNowPlayingInfoFn? = nil
    private var registerForNotificationsFn: MRRegisterForNowPlayingNotificationsFn? = nil
    private var sendCommandFn: MRSendCommandFn? = nil
    private var getIsPlayingFn: MRGetNowPlayingApplicationIsPlayingFn? = nil
    
    init() {
        setupMediaRemote()
        startPolling()
    }
    
    deinit {
        stopPolling()
        NotificationCenter.default.removeObserver(self)
        if let h = mediaRemoteHandle {
            dlclose(h)
        }
    }
    
    private func setupMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            logToFile("[MediaService] Could not dlopen MediaRemote.framework — AppleScript only")
            return
        }
        self.mediaRemoteHandle = handle
        
        if let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            self.registerForNotificationsFn = unsafeBitCast(regSym, to: MRRegisterForNowPlayingNotificationsFn.self)
            // macOS 13+: register on main before get-callbacks reliably fire
            self.registerForNotificationsFn?(DispatchQueue.main)
            logToFile("[MediaService] Registered for MediaRemote notifications")
        }
        
        if let getSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            self.getNowPlayingInfoFn = unsafeBitCast(getSym, to: MRGetNowPlayingInfoFn.self)
            logToFile("[MediaService] Bound MRMediaRemoteGetNowPlayingInfo")
        } else {
            logToFile("[MediaService] MRMediaRemoteGetNowPlayingInfo symbol missing")
        }
        
        if let playSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            self.getIsPlayingFn = unsafeBitCast(playSym, to: MRGetNowPlayingApplicationIsPlayingFn.self)
        }
        
        if let sendSym = dlsym(handle, "MRMediaRemoteSendCommand") {
            self.sendCommandFn = unsafeBitCast(sendSym, to: MRSendCommandFn.self)
        }
        
        // Notification name is the *value* of the exported CFStringRef, not the C symbol name.
        observeMediaRemoteNotification(
            handle: handle,
            symbol: "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
        )
        observeMediaRemoteNotification(
            handle: handle,
            symbol: "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
        )
        observeMediaRemoteNotification(
            handle: handle,
            symbol: "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        )
    }
    
    private func observeMediaRemoteNotification(handle: UnsafeMutableRawPointer, symbol: String) {
        guard let nameSym = dlsym(handle, symbol) else { return }
        let cfName = nameSym.assumingMemoryBound(to: CFString.self).pointee
        let noteName = NSNotification.Name(cfName as String)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaNotification),
            name: noteName,
            object: nil
        )
        logToFile("[MediaService] Observing notification: \(noteName.rawValue)")
    }
    
    @objc private func handleMediaNotification() {
        updateMediaState()
    }
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMediaState()
        }
        // Ensure timer fires while scrolling / notch animating
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        updateMediaState()
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    private func logToFile(_ message: String) {
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
    
    func updateMediaState() {
        guard let getInfo = getNowPlayingInfoFn else {
            updateViaAppleScript(force: false)
            return
        }
        
        getInfo(DispatchQueue.main) { [weak self] dict in
            guard let self = self else { return }
            
            guard let info = dict, !info.isEmpty else {
                self.emptyTicksCount += 1
                self.logToFile("[MediaService] MediaRemote empty (tick \(self.emptyTicksCount))")
                if self.emptyTicksCount >= 1 {
                    self.updateViaAppleScript(force: false)
                }
                return
            }
            
            let title = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let artist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let album = (info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            var rate: Double = 0
            if let num = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber {
                rate = num.doubleValue
            } else if let dbl = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                rate = dbl
            }
            
            var elapsed: Double = 0
            if let num = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber {
                elapsed = num.doubleValue
            } else if let dbl = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double {
                elapsed = dbl
            }
            
            var total: Double = 0
            if let num = info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber {
                total = num.doubleValue
            } else if let dbl = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double {
                total = dbl
            }
            
            // Artwork may arrive as Data or NSData
            var artwork: NSImage? = nil
            if let raw = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                artwork = NSImage(data: raw)
            } else if let raw = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? NSData {
                artwork = NSImage(data: raw as Data)
            }
            
            if title.isEmpty {
                self.emptyTicksCount += 1
                self.logToFile("[MediaService] MediaRemote dict without title keys=\(Array(info.keys))")
                if self.emptyTicksCount >= 1 {
                    self.updateViaAppleScript(force: false)
                }
                return
            }
            
            self.emptyTicksCount = 0
            
            let apply: (Bool) -> Void = { playing in
                self.currentTitle = title
                self.currentArtist = artist.isEmpty ? (album.isEmpty ? "Now Playing" : album) : artist
                self.isPlaying = playing
                self.sourceApp = "System"
                self.elapsedTime = elapsed
                self.duration = total
                
                let trackKey = "\(title)-\(artist)"
                self.logToFile("[MediaService] MediaRemote: \(title) — \(artist) playing=\(playing)")
                
                if let artwork = artwork {
                    self.albumArtworkImage = artwork
                    self.lastFetchedTrack = trackKey
                } else if trackKey != self.lastFetchedTrack {
                    self.fetchAlbumArtwork(title: title, artist: artist)
                }
            }
            
            if let getPlaying = self.getIsPlayingFn {
                getPlaying(DispatchQueue.main) { playing in
                    // Prefer dedicated isPlaying; fall back to rate if needed
                    apply(playing || rate > 0)
                }
            } else {
                apply(rate > 0)
            }
        }
    }
    
    // MARK: - AppleScript Fallback (Spotify / Music)
    private func updateViaAppleScript(force: Bool) {
        let now = Date()
        if !force {
            if appleScriptBusy { return }
            if now.timeIntervalSince(lastAppleScriptAt) < 1.5 { return }
        }
        appleScriptBusy = true
        lastAppleScriptAt = now
        
        let queue = DispatchQueue(label: "com.jarvis.appleScriptQueue", qos: .userInitiated)
        queue.async { [weak self] in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.appleScriptBusy = false }
            }
            
            // Spotify first (most common for Latin / streaming)
            let spotifyScript = """
            if application "Spotify" is running then
                tell application "Spotify"
                    try
                        set pState to player state as string
                        set tName to name of current track
                        set aName to artist of current track
                        set aUrl to artwork url of current track
                        return pState & "|||" & tName & "|||" & aName & "|||" & aUrl
                    on error errMsg
                        return "error|||" & errMsg
                    end try
                end tell
            else
                return "notrunning"
            end if
            """
            
            let musicScript = """
            if application "Music" is running then
                tell application "Music"
                    try
                        set pState to player state as string
                        set tName to name of current track
                        set aName to artist of current track
                        return pState & "|||" & tName & "|||" & aName
                    on error errMsg
                        return "error|||" & errMsg
                    end try
                end tell
            else
                return "notrunning"
            end if
            """
            
            if let spotifyRes = self.runAppleScript(spotifyScript),
               spotifyRes != "notrunning",
               !spotifyRes.hasPrefix("error|||"),
               !spotifyRes.isEmpty {
                let parts = spotifyRes.components(separatedBy: "|||")
                if parts.count >= 3, !parts[1].isEmpty {
                    let playingState = parts[0].lowercased()
                    let playing = playingState.contains("play")
                    let spotArtUrl = parts.count >= 4 ? parts[3] : nil
                    self.logToFile("[MediaService] AppleScript Spotify: \(parts[1]) playing=\(playing)")
                    DispatchQueue.main.async {
                        self.emptyTicksCount = 0
                        self.currentTitle = parts[1]
                        self.currentArtist = parts[2]
                        self.isPlaying = playing
                        self.sourceApp = "Spotify"
                        self.fetchAlbumArtwork(title: parts[1], artist: parts[2], spotifyArtworkUrl: spotArtUrl)
                    }
                    return
                }
            } else if let spotifyRes = self.runAppleScript(spotifyScript) {
                self.logToFile("[MediaService] Spotify script: \(spotifyRes.prefix(120))")
            }
            
            if let musicRes = self.runAppleScript(musicScript),
               musicRes != "notrunning",
               !musicRes.hasPrefix("error|||"),
               !musicRes.isEmpty {
                let parts = musicRes.components(separatedBy: "|||")
                if parts.count >= 3, !parts[1].isEmpty {
                    let playingState = parts[0].lowercased()
                    let playing = playingState.contains("play")
                    self.logToFile("[MediaService] AppleScript Music: \(parts[1]) playing=\(playing)")
                    DispatchQueue.main.async {
                        self.emptyTicksCount = 0
                        self.currentTitle = parts[1]
                        self.currentArtist = parts[2]
                        self.isPlaying = playing
                        self.sourceApp = "Music"
                        self.fetchAlbumArtwork(title: parts[1], artist: parts[2])
                    }
                    return
                }
            }
            
            // Only clear UI after several consecutive misses (avoid flicker)
            DispatchQueue.main.async {
                self.emptyTicksCount += 1
                if self.emptyTicksCount >= 4 {
                    if self.currentTitle != "No Reproduciendo" {
                        self.logToFile("[MediaService] Clearing now-playing after misses")
                    }
                    self.currentTitle = "No Reproduciendo"
                    self.currentArtist = ""
                    self.isPlaying = false
                    self.sourceApp = ""
                    self.albumArtworkImage = nil
                    self.lastFetchedTrack = ""
                    self.elapsedTime = 0
                    self.duration = 0
                }
            }
        }
    }
    
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error = error {
            logToFile("[MediaService] AppleScript error: \(error)")
            return nil
        }
        return output.stringValue
    }
    
    // MARK: - Artwork Fetcher
    private func fetchAlbumArtwork(title: String, artist: String, spotifyArtworkUrl: String? = nil) {
        let trackKey = "\(title)-\(artist)"
        guard trackKey != lastFetchedTrack else { return }
        lastFetchedTrack = trackKey
        
        if let spotUrlString = spotifyArtworkUrl, !spotUrlString.isEmpty, let spotUrl = URL(string: spotUrlString) {
            downloadImage(from: spotUrl)
            return
        }
        
        let cleanedQuery = cleanQueryString(title: title, artist: artist)
        guard !cleanedQuery.isEmpty,
              let searchUrl = URL(string: "https://itunes.apple.com/search?term=\(cleanedQuery)&entity=song&limit=1") else { return }
        
        URLSession.shared.dataTask(with: searchUrl) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            struct iTunesResult: Codable {
                struct Track: Codable { let artworkUrl100: String? }
                let results: [Track]
            }
            do {
                let res = try JSONDecoder().decode(iTunesResult.self, from: data)
                if let rawUrlString = res.results.first?.artworkUrl100 {
                    let highResUrlString = rawUrlString.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    if let imgUrl = URL(string: highResUrlString) {
                        self?.downloadImage(from: imgUrl)
                    }
                }
            } catch {
                print("Failed to decode iTunes artwork: \(error)")
            }
        }.resume()
    }
    
    private func cleanQueryString(title: String, artist: String) -> String {
        var clean = "\(title) \(artist)"
        let clutter = [
            "Official Video", "Official Music Video", "Lyric Video", "Audio",
            "Full Video", "HD", "4K", "Remix", "Mix", "(Official Video)",
            "(Lyric Video)", "[Official Music Video]", "[Official Video]", "[Audio]"
        ]
        for word in clutter {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        let words = clean.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
        let shortened = words.prefix(4).joined(separator: " ")
        return shortened.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
    
    private func downloadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.albumArtworkImage = image
            }
        }.resume()
    }
    
    // MARK: - System-Wide Media Controls
    func playPause() {
        if let send = sendCommandFn {
            _ = send(0, nil) // Toggle Play/Pause
        } else if sourceApp == "Spotify" {
            _ = runAppleScript("tell application \"Spotify\" to playpause")
        } else if sourceApp == "Music" {
            _ = runAppleScript("tell application \"Music\" to playpause")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.updateMediaState()
        }
    }
    
    func nextTrack() {
        if let send = sendCommandFn {
            _ = send(4, nil)
        } else if sourceApp == "Spotify" {
            _ = runAppleScript("tell application \"Spotify\" to next track")
        } else if sourceApp == "Music" {
            _ = runAppleScript("tell application \"Music\" to next track")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.updateMediaState()
        }
    }
    
    func previousTrack() {
        if let send = sendCommandFn {
            _ = send(5, nil)
        } else if sourceApp == "Spotify" {
            _ = runAppleScript("tell application \"Spotify\" to previous track")
        } else if sourceApp == "Music" {
            _ = runAppleScript("tell application \"Music\" to previous track")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.updateMediaState()
        }
    }
}
