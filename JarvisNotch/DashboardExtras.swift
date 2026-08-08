import SwiftUI
import AppKit
import EventKit

// MARK: - Calendar

struct JarvisCalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    
    var timeRange: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "H:mm"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}

class CalendarService: ObservableObject {
    @Published var events: [JarvisCalendarEvent] = []
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published var accessGranted: Bool = false
    
    private let store = EKEventStore()
    private var refreshTimer: Timer?
    
    init() {
        requestAccessAndLoad()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.loadEvents()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    var nearbyDays: [Date] {
        let cal = Calendar.current
        return (-1...1).compactMap { cal.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }
    
    func requestAccessAndLoad() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.loadEvents() }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.loadEvents() }
                }
            }
        }
    }
    
    func loadEvents() {
        guard accessGranted else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDay)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
        
        events = ekEvents.map { ev in
            let color: Color
            if let cg = ev.calendar.cgColor, let ns = NSColor(cgColor: cg) {
                color = Color(nsColor: ns)
            } else {
                color = .purple
            }
            return JarvisCalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "Sin título",
                start: ev.startDate,
                end: ev.endDate,
                color: color
            )
        }
    }
    
    func selectDay(_ day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        loadEvents()
    }
    
    func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

// MARK: - Focus Timer

class FocusTimerService: ObservableObject {
    @Published var remainingSeconds: Int
    @Published var isRunning: Bool = false
    @Published var sessionIndex: Int
    @Published var totalSessions: Int = 3
    
    private let workMinutesKey = "jarvisFocusMinutes"
    private let sessionKey = "jarvisFocusSession"
    private var timer: Timer?
    private var workSeconds: Int
    
    init() {
        let mins = UserDefaults.standard.object(forKey: workMinutesKey) as? Int ?? 25
        workSeconds = max(5, mins) * 60
        remainingSeconds = workSeconds
        sessionIndex = max(1, UserDefaults.standard.integer(forKey: sessionKey) == 0 ? 1 : UserDefaults.standard.integer(forKey: sessionKey))
    }
    
    deinit {
        timer?.invalidate()
    }
    
    var displayTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    var progress: Double {
        guard workSeconds > 0 else { return 0 }
        return 1.0 - (Double(remainingSeconds) / Double(workSeconds))
    }
    
    func toggle() {
        isRunning ? pause() : start()
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            } else {
                self.completeSession()
            }
        }
    }
    
    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func reset() {
        pause()
        remainingSeconds = workSeconds
    }
    
    func skip() {
        completeSession()
    }
    
    private func completeSession() {
        pause()
        sessionIndex = sessionIndex >= totalSessions ? 1 : sessionIndex + 1
        UserDefaults.standard.set(sessionIndex, forKey: sessionKey)
        remainingSeconds = workSeconds
        NSSound.beep()
    }
}

// MARK: - Quick Note

class QuickNoteStore: ObservableObject {
    @Published var text: String {
        didSet { UserDefaults.standard.set(text, forKey: Self.key) }
    }
    
    private static let key = "jarvisQuickNote"
    
    static let sparks = [
        "Tu futuro lo construyes con lo que haces hoy.",
        "Un paso pequeño sigue siendo avance.",
        "Enfócate en una sola cosa a la vez.",
        "La constancia vence al talento sin disciplina."
    ]
    
    init() {
        text = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }
    
    var placeholder: String {
        Self.sparks[abs(Calendar.current.component(.day, from: Date())) % Self.sparks.count]
    }
}

// MARK: - App Launcher

struct LaunchableApp: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let tint: Color
    let bundleIds: [String]
    let pathHints: [String]
}

enum AppLauncher {
    static let apps: [LaunchableApp] = [
        LaunchableApp(name: "Safari", symbol: "safari.fill", tint: .blue,
                      bundleIds: ["com.apple.Safari"], pathHints: ["/Applications/Safari.app"]),
        LaunchableApp(name: "Notas", symbol: "note.text", tint: .yellow,
                      bundleIds: ["com.apple.Notes"], pathHints: ["/System/Applications/Notes.app"]),
        LaunchableApp(name: "Mensajes", symbol: "message.fill", tint: .green,
                      bundleIds: ["com.apple.MobileSMS"], pathHints: ["/System/Applications/Messages.app"]),
        LaunchableApp(name: "Música", symbol: "music.note", tint: .pink,
                      bundleIds: ["com.apple.Music"], pathHints: ["/System/Applications/Music.app"]),
        LaunchableApp(name: "Spotify", symbol: "waveform", tint: .green,
                      bundleIds: ["com.spotify.client"], pathHints: ["/Applications/Spotify.app"]),
        LaunchableApp(name: "Terminal", symbol: "terminal.fill", tint: .gray,
                      bundleIds: ["com.apple.Terminal"], pathHints: ["/System/Applications/Utilities/Terminal.app"]),
        LaunchableApp(name: "Finder", symbol: "folder.fill", tint: .cyan,
                      bundleIds: ["com.apple.finder"], pathHints: ["/System/Library/CoreServices/Finder.app"]),
        LaunchableApp(name: "Ajustes", symbol: "gearshape.fill", tint: .orange,
                      bundleIds: ["com.apple.systempreferences", "com.apple.Preferences"],
                      pathHints: ["/System/Applications/System Settings.app"])
    ]
    
    static func open(_ app: LaunchableApp) {
        for bid in app.bundleIds {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        for path in app.pathHints {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }
}

// MARK: - Widget Views

struct CalendarWidget: View {
    @ObservedObject var calendar: CalendarService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(monthLabel)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white.opacity(0.85))
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundColor(.purple)
                Spacer()
                Button(action: { calendar.openCalendarApp() }) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            
            if !calendar.accessGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Permite acceso al calendario")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                    Button("Autorizar") { calendar.requestAccessAndLoad() }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.purple)
                        .buttonStyle(.plain)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            } else if calendar.events.isEmpty {
                Text("Sin eventos este día")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(calendar.events.prefix(3)) { event in
                        HStack(alignment: .top, spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(event.color)
                                .frame(width: 2.5, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(event.timeRange)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            
            HStack(spacing: 4) {
                ForEach(calendar.nearbyDays, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay)
                    Button(action: { calendar.selectDay(day) }) {
                        VStack(spacing: 1) {
                            Text(weekday(day))
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(selected ? .black : .white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.white : Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(width: 150, height: 215)
        .background(widgetBackground)
    }
    
    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMM"
        return f.string(from: calendar.selectedDay).uppercased()
    }
    
    private func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }
}

struct AppsWidget: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        VStack(spacing: 8) {
            Text("APPS")
                .font(.system(size: 9, weight: .black))
                .tracking(1)
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AppLauncher.apps.prefix(6)) { app in
                    Button(action: { AppLauncher.open(app) }) {
                        VStack(spacing: 4) {
                            Image(systemName: app.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(app.tint)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 8).fill(app.tint.opacity(0.18)))
                            Text(app.name)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 108, height: 215)
        .background(widgetBackground)
    }
}

struct NoteWidget: View {
    @ObservedObject var note: QuickNoteStore
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isEditing ? "Escribe algo…" : "En mente")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            
            if isEditing {
                TextEditor(text: $note.text)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: .infinity)
            } else {
                Text(note.text.isEmpty ? note.placeholder : note.text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(note.text.isEmpty ? 0.65 : 0.95))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onTapGesture { isEditing = true }
            }
            
            HStack {
                Button(action: {
                    isEditing.toggle()
                }) {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isEditing ? .green : .purple.opacity(0.9))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(10)
        .frame(width: 150, height: 100)
        .background(widgetBackground)
    }
}

struct FocusWidget: View {
    @ObservedObject var focus: FocusTimerService
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.cyan)
                Text("Foco (\(focus.sessionIndex)/\(focus.totalSessions))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            
            Text(focus.displayTime)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                )
                .monospacedDigit()
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * focus.progress))
                }
            }
            .frame(height: 3)
            
            HStack(spacing: 12) {
                focusButton(icon: "arrow.counterclockwise", action: focus.reset)
                focusButton(icon: focus.isRunning ? "pause.fill" : "play.fill", action: focus.toggle, emphasized: true)
                focusButton(icon: "forward.fill", action: focus.skip)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 150, height: 105)
        .background(widgetBackground)
    }
    
    private func focusButton(icon: String, action: @escaping () -> Void, emphasized: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: emphasized ? 11 : 10, weight: .bold))
                .foregroundColor(.white.opacity(emphasized ? 1 : 0.75))
                .frame(width: emphasized ? 28 : 24, height: emphasized ? 28 : 24)
                .background(Circle().fill(Color.white.opacity(emphasized ? 0.18 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

private var widgetBackground: some View {
    RoundedRectangle(cornerRadius: 14)
        .fill(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
}
