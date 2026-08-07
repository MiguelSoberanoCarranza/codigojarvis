import Foundation
import AppKit

class MediaService: ObservableObject {
    @Published var currentTitle: String = "No Reproduciendo"
    @Published var currentArtist: String = ""
    @Published var isPlaying: Bool = false
    @Published var sourceApp: String = ""
    @Published var albumArtworkImage: NSImage? = nil
    
    private var timer: Timer?
    private var lastFetchedTrack: String = ""
    private var emptyTicksCount: Int = 0
    private var mediaRemoteHandle: UnsafeMutableRawPointer? = nil
    
    private typealias MRMediaRemoteGetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void
    private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias MRMediaRemoteSendCommandFn = @convention(c) (Int32, AnyObject?) -> Bool
    
    private var getNowPlayingInfoFn: MRMediaRemoteGetNowPlayingInfoFn? = nil
    private var registerForNotificationsFn: MRMediaRemoteRegisterForNowPlayingNotificationsFn? = nil
    private var sendCommandFn: MRMediaRemoteSendCommandFn? = nil
    
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
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            logToFile("[MediaService] Could not dlopen MediaRemote.framework")
            return
        }
        self.mediaRemoteHandle = handle
        
        if let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            self.registerForNotificationsFn = unsafeBitCast(regSym, to: MRMediaRemoteRegisterForNowPlayingNotificationsFn.self)
            self.registerForNotificationsFn?(DispatchQueue.global(qos: .userInitiated))
            logToFile("[MediaService] Registered for MediaRemote notifications successfully!")
        }
        
        if let getSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            self.getNowPlayingInfoFn = unsafeBitCast(getSym, to: MRMediaRemoteGetNowPlayingInfoFn.self)
        }
        
        if let sendSym = dlsym(handle, "MRMediaRemoteSendCommand") {
            self.sendCommandFn = unsafeBitCast(sendSym, to: MRMediaRemoteSendCommandFn.self)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaNotification),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil
        )
    }
    
    @objc private func handleMediaNotification() {
        updateMediaState()
    }
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMediaState()
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
            updateViaAppleScript()
            return
        }
        
        getInfo(DispatchQueue.global(qos: .userInitiated)) { [weak self] dict in
            guard let self = self else { return }
            let nsDict = dict as NSDictionary
            
            let title = nsDict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let artist = nsDict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            
            var rate: Double = 0.0
            if let num = nsDict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber {
                rate = num.doubleValue
            } else if let dbl = nsDict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                rate = dbl
            }
            
            DispatchQueue.main.async {
                if !title.isEmpty {
                    self.emptyTicksCount = 0
                    self.currentTitle = title
                    self.currentArtist = artist.isEmpty ? "YouTube / Web" : artist
                    self.isPlaying = rate > 0.0
                    self.sourceApp = "System"
                    
                    let trackKey = "\(title)-\(artist)"
                    self.logToFile("[MediaService] Active track: \(title) by \(artist) [playing=\(self.isPlaying)]")
                    
                    // Extract raw image data if provided by MediaRemote (e.g. YouTube video thumbnail or album art)
                    var foundImage = false
                    if let rawData = nsDict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, let img = NSImage(data: rawData) {
                        self.albumArtworkImage = img
                        self.lastFetchedTrack = trackKey
                        foundImage = true
                    } else if let nsData = nsDict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? NSData, let img = NSImage(data: nsData as Data) {
                        self.albumArtworkImage = img
                        self.lastFetchedTrack = trackKey
                        foundImage = true
                    }
                    
                    if !foundImage && trackKey != self.lastFetchedTrack {
                        self.fetchAlbumArtwork(title: title, artist: artist)
                    }
                } else {
                    self.emptyTicksCount += 1
                    if self.emptyTicksCount >= 3 {
                        if self.currentTitle != "No Reproduciendo" {
                            self.isPlaying = false
                        } else {
                            self.updateViaAppleScript()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - AppleScript Fallback
    private func updateViaAppleScript() {
        let queue = DispatchQueue(label: "com.jarvis.appleScriptQueue", qos: .userInitiated)
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let spotifyScript = """
            if application "Spotify" is running then
                tell application "Spotify"
                    try
                        set pState to player state as string
                        set tName to name of current track
                        set aName to artist of current track
                        set aUrl to artwork url of current track
                        return pState & "|" & tName & "|" & aName & "|" & aUrl
                    on error
                        return "stopped|||"
                    end try
                end tell
            else
                return "stopped|||"
            end if
            """
            
            let musicScript = """
            if application "Music" is running then
                tell application "Music"
                    try
                        set pState to player state as string
                        set tName to name of current track
                        set aName to artist of current track
                        return pState & "|" & tName & "|" & aName
                    on error
                        return "stopped||"
                    end try
                end tell
            else
                return "stopped||"
            end if
            """
            
            if let spotifyRes = self.runAppleScript(spotifyScript), spotifyRes != "stopped|||", !spotifyRes.isEmpty {
                let parts = spotifyRes.components(separatedBy: "|")
                if parts.count >= 3 && !parts[1].isEmpty {
                    let playingState = parts[0].lowercased()
                    let playing = playingState.contains("play") || playingState == "kpsp"
                    let spotArtUrl = parts.count >= 4 ? parts[3] : nil
                    
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
            }
            
            if let musicRes = self.runAppleScript(musicScript), musicRes != "stopped||", !musicRes.isEmpty {
                let parts = musicRes.components(separatedBy: "|")
                if parts.count >= 3 && !parts[1].isEmpty {
                    let playingState = parts[0].lowercased()
                    let playing = playingState.contains("play") || playingState == "kpsp"
                    
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
            
            DispatchQueue.main.async {
                self.currentTitle = "No Reproduciendo"
                self.currentArtist = ""
                self.isPlaying = false
                self.sourceApp = ""
                self.albumArtworkImage = nil
                self.lastFetchedTrack = ""
            }
        }
    }
    
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
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
        guard !cleanedQuery.isEmpty, let searchUrl = URL(string: "https://itunes.apple.com/search?term=\(cleanedQuery)&entity=song&limit=1") else { return }
        
        URLSession.shared.dataTask(with: searchUrl) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            struct iTunesResult: Codable {
                struct Track: Codable {
                    let artworkUrl100: String?
                }
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
        let clutter = ["Official Video", "Official Music Video", "Lyric Video", "Audio", "Full Video", "HD", "4K", "Remix", "Mix", "Style", "#1", "#2", "(Official Video)", "(Lyric Video)", "[Official Music Video]", "[Official Video]", "[Audio]"]
        for word in clutter {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        let words = clean.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
        let shortened = words.prefix(4).joined(separator: " ")
        return shortened.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
    
    private func downloadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.albumArtworkImage = image
            }
        }.resume()
    }
    
    // MARK: - System-Wide Media Controls
    func playPause() {
        if let send = sendCommandFn {
            _ = send(0, nil) // 0 = Toggle Play/Pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.updateMediaState()
            }
        }
    }
    
    func nextTrack() {
        if let send = sendCommandFn {
            _ = send(4, nil) // 4 = Next Track
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.updateMediaState()
            }
        }
    }
    
    func previousTrack() {
        if let send = sendCommandFn {
            _ = send(5, nil) // 5 = Previous Track
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.updateMediaState()
            }
        }
    }
}
