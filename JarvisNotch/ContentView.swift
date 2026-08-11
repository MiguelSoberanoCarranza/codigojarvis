import SwiftUI
import AppKit
import IOKit.ps

struct ContentView: View {
    @ObservedObject var stateManager: NotchStateManager
    @StateObject private var mediaService = MediaService()
    @StateObject private var weatherService = WeatherService()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var focusTimer = FocusTimerService()
    @StateObject private var quickNote = QuickNoteStore()
    @StateObject private var aiSpendStore = AISpendStore()
    
    @State private var batteryPercentage: Int = 100
    @State private var isCharging: Bool = false
    @State private var systemVolume: Double = 50.0
    @State private var isTargetedForDrop: Bool = false
    @State private var droppedFiles: [URL] = []
    @State private var isShowingSettings: Bool = false
    
    let sysTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    /// Collapsed pill is visible only when the setting is on (or while expanded).
    private var isCollapsedVisible: Bool {
        stateManager.isExpanded || stateManager.showMinimizedDisplay
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // 1. Morphing Black Dynamic Island Background Container
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: stateManager.isExpanded ? 32 : 12,
                bottomTrailingRadius: stateManager.isExpanded ? 32 : 12,
                topTrailingRadius: 0
            )
            .fill(Color.black)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: stateManager.isExpanded ? 32 : 12,
                    bottomTrailingRadius: stateManager.isExpanded ? 32 : 12,
                    topTrailingRadius: 0
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(stateManager.isExpanded ? 0.25 : 0.12),
                            .purple.opacity(stateManager.isExpanded ? 0.4 : 0.0),
                            .blue.opacity(stateManager.isExpanded ? 0.4 : 0.0),
                            .white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .frame(
                width: stateManager.isExpanded ? stateManager.expandedWidth : stateManager.collapsedWidth,
                height: max(stateManager.collapsedHeight, stateManager.isExpanded ? stateManager.expandedHeight : stateManager.collapsedHeight)
            )
            .shadow(
                color: Color.black.opacity(stateManager.isExpanded ? 0.4 : 0.0),
                radius: stateManager.isExpanded ? 20 : 0,
                x: 0,
                y: 10
            )
            
            // 2. Inner Content (Fades & Morphing transitions)
            ZStack(alignment: .top) {
                if stateManager.isExpanded {
                    if isShowingSettings {
                        settingsView
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
                    } else {
                        dashboardView
                            .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
                    }
                } else if stateManager.showMinimizedDisplay {
                    collapsedPill
                        .transition(.opacity)
                }
            }
            .frame(
                width: stateManager.isExpanded ? stateManager.expandedWidth : stateManager.collapsedWidth,
                height: max(stateManager.collapsedHeight, stateManager.isExpanded ? stateManager.expandedHeight : stateManager.collapsedHeight)
            )
        }
        .opacity(isCollapsedVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: stateManager.showMinimizedDisplay)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onReceive(sysTimer) { _ in
            updateSystemStatus()
        }
        .onAppear {
            updateSystemStatus()
            fetchInitialVolume()
        }
    }
    
    // MARK: - Collapsed Dynamic Island Pill
    private var collapsedPill: some View {
        HStack(spacing: 0) {
            // Left Wing (Weather)
            HStack(spacing: 4) {
                Text(weatherService.conditionEmoji)
                    .font(.system(size: 11))
                Text(weatherService.temperature)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(width: 80, height: stateManager.collapsedHeight)
            
            Spacer() // Center Gap (matching physical camera notch)
                .frame(width: 158)
            
            // Right Wing (Battery / Live Music Equalizer)
            HStack(spacing: 6) {
                if mediaService.isPlaying {
                    Image(systemName: "music.note")
                        .foregroundColor(.pink)
                        .font(.system(size: 10, weight: .bold))
                    AudioWaveformView()
                } else {
                    Image(systemName: isCharging ? "battery.100.bolt" : "battery.75")
                        .foregroundColor(isCharging ? .green : .white.opacity(0.7))
                        .font(.system(size: 10))
                    Text("\(batteryPercentage)%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(width: 80, height: stateManager.collapsedHeight)
        }
        .frame(width: stateManager.collapsedWidth, height: stateManager.collapsedHeight)
    }
    
    // MARK: - Expanded Dashboard View
    private var dashboardView: some View {
        VStack(spacing: 10) {
            // Top Header Bar
            HStack(spacing: 10) {
                Text("JARVIS NOTCH")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Spacer()
                
                // Weather chip in header
                HStack(spacing: 4) {
                    Text(weatherService.conditionEmoji)
                        .font(.system(size: 11))
                    Text(weatherService.temperature)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text(weatherService.city)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                
                // Settings / Shortcuts Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isShowingSettings.toggle()
                    }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                
                // Battery Badge
                HStack(spacing: 4) {
                    Image(systemName: isCharging ? "battery.100.bolt" : "battery.100")
                        .foregroundColor(isCharging ? .green : .white.opacity(0.8))
                    Text("\(batteryPercentage)%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 14)
            .padding(.top, stateManager.collapsedHeight - 16 + 4)
            
            // Dashboard strip: music + calendar + apps + note/focus + AI spend limits
            HStack(alignment: .top, spacing: 10) {
                musicCard
                CalendarWidget(calendar: calendarService)
                AppsWidget()
                VStack(spacing: 10) {
                    NoteWidget(note: quickNote)
                    FocusWidget(focus: focusTimer)
                }
                AISpendWidget(store: aiSpendStore)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: stateManager.expandedWidth, height: stateManager.expandedHeight)
    }
    
    // MARK: - Quick Shortcuts & Settings View
    private var settingsView: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isShowingSettings = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("AJUSTES Y ATAJOS")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.5)
                    }
                    .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isShowingSettings = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, stateManager.collapsedHeight - 16 + 6)
            
            // Shortcuts 2x3 Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // 1. Lock Screen
                shortcutButton(icon: "lock.fill", title: "Bloquear", color: .red) {
                    executeAppleScript("tell application \"System Events\" to start current screen saver")
                }
                
                // 2. Interactive Screenshot
                shortcutButton(icon: "camera.viewfinder", title: "Captura", color: .blue) {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let task = Process()
                        task.launchPath = "/usr/sbin/screencapture"
                        task.arguments = ["-ic"]
                        try? task.run()
                    }
                }
                
                // 3. Dark Mode Toggle
                shortcutButton(icon: "moon.stars.fill", title: "Modo Oscuro", color: .purple) {
                    executeAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
                }
                
                // 4. Mute / Unmute Volume
                shortcutButton(icon: systemVolume == 0 ? "speaker.wave.3.fill" : "speaker.slash.fill", title: systemVolume == 0 ? "Desmutear" : "Silenciar", color: .orange) {
                    if systemVolume == 0 {
                        setSystemVolume(to: 50.0)
                        systemVolume = 50.0
                    } else {
                        setSystemVolume(to: 0.0)
                        systemVolume = 0.0
                    }
                }
                
                // 5. Refresh Weather & Location
                shortcutButton(icon: "arrow.triangle.2.circlepath", title: "Ubicación", color: .green) {
                    weatherService.refreshWeather()
                }
                
                // 6. Empty Trash
                shortcutButton(icon: "trash.fill", title: "Papelera", color: .gray) {
                    executeAppleScript("tell application \"Finder\" to empty trash")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Minimized display toggle — hides collapsed wings that cover the menu bar / top UI
            HStack(spacing: 12) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.cyan)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.cyan.opacity(0.18)))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mostrar minimizado")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("Clima y batería a los lados del notch. Desactívalo si tapa la barra de menús.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 8)
                
                Toggle("", isOn: Binding(
                    get: { stateManager.showMinimizedDisplay },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            stateManager.showMinimizedDisplay = newValue
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            Text("YouTube en Chrome/Safari: activa “Allow JavaScript from Apple Events” en el menú Desarrollador del navegador, y permite Automatización a JarvisNotch.")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 18)
                .padding(.top, 2)
            
            Spacer()
        }
        .frame(width: stateManager.expandedWidth, height: stateManager.expandedHeight)
    }
    
    private func shortcutButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Subcards
    private var musicCard: some View {
        VStack(spacing: 8) {
            VinylDiscView(mediaService: mediaService)
            
            VStack(spacing: 2) {
                Text(mediaService.currentTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(mediaService.currentArtist.isEmpty ? (mediaService.isPlaying ? "Reproduciendo" : "Sin reproducción") : mediaService.currentArtist)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            
            // Media Controls
            HStack(spacing: 14) {
                Button(action: { mediaService.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                
                Button(action: { mediaService.playPause() }) {
                    Image(systemName: mediaService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                
                Button(action: { mediaService.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
            
            HStack(spacing: 6) {
                Image(systemName: systemVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.7))
                
                Slider(value: $systemVolume, in: 0...100, onEditingChanged: { _ in
                    setSystemVolume(to: systemVolume)
                })
                .accentColor(.purple)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 150, height: 215)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Helper Functions
    private func executeAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
            }
        }
    }
    
    private func updateSystemStatus() {
        let (pct, charging) = getBatteryInfo()
        self.batteryPercentage = pct
        self.isCharging = charging
    }
    
    private func getBatteryInfo() -> (percentage: Int, isCharging: Bool) {
        #if targetEnvironment(simulator)
        return (80, true)
        #else
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (100, false)
        }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (100, false)
        }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? 100
                let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
                return (capacity, isCharging)
            }
        }
        return (100, false)
        #endif
    }
    
    private func fetchInitialVolume() {
        DispatchQueue.global(qos: .userInitiated).async {
            let vol = getSystemVolume()
            DispatchQueue.main.async {
                self.systemVolume = vol
            }
        }
    }
    
    private func getSystemVolume() -> Double {
        let script = "output volume of (get volume settings)"
        if let scriptObject = NSAppleScript(source: script) {
            var error: NSDictionary?
            let descriptor = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return Double(descriptor.int32Value)
            }
        }
        return 50.0
    }
    
    private func setSystemVolume(to value: Double) {
        let vol = Int(value)
        let script = "set volume output volume \(vol)"
        if let scriptObject = NSAppleScript(source: script) {
            var error: NSDictionary?
            scriptObject.executeAndReturnError(&error)
        }
    }
}

// MARK: - Audio Waveform Animation for Dynamic Island
struct AudioWaveformView: View {
    @State private var barHeights: [CGFloat] = [0.3, 0.8, 0.5, 0.9]
    let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: 12 * barHeights[index])
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                barHeights = [
                    CGFloat.random(in: 0.2...1.0),
                    CGFloat.random(in: 0.2...1.0),
                    CGFloat.random(in: 0.2...1.0),
                    CGFloat.random(in: 0.2...1.0)
                ]
            }
        }
    }
}

// MARK: - Vinyl Disc Component with Reliable Animation
struct VinylDiscView: View {
    @ObservedObject var mediaService: MediaService
    @State private var rotationDegrees: Double = 0.0
    
    let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            if let artwork = mediaService.albumArtworkImage {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.init(white: 0.15), .init(white: 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 46, height: 46)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 34, height: 34)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: mediaService.isPlaying ? [.pink, .purple] : [.gray.opacity(0.6), .gray.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                
                Image(systemName: mediaService.isPlaying ? "music.note" : "play.slash.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .rotationEffect(.degrees(rotationDegrees))
        .onReceive(timer) { _ in
            if mediaService.isPlaying {
                rotationDegrees = (rotationDegrees + 2.5).truncatingRemainder(dividingBy: 360.0)
            }
        }
    }
}
