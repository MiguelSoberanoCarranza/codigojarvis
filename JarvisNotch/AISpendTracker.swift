import SwiftUI
import AppKit

struct AIProviderBudget: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var spent: Double
    var limit: Double
    var accentHex: String
    var billingURL: String
    var enabled: Bool
    
    var accent: Color {
        Color(hex: accentHex) ?? .purple
    }
    
    var ratio: Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, spent / limit))
    }
    
    var remaining: Double {
        max(0, limit - spent)
    }
    
    var isOverLimit: Bool {
        spent >= limit && limit > 0
    }
    
    var spentLabel: String {
        Self.formatMoney(spent)
    }
    
    var limitLabel: String {
        Self.formatMoney(limit)
    }
    
    static func formatMoney(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.0f", value)
        }
        if value == floor(value) {
            return String(format: "$%.0f", value)
        }
        return String(format: "$%.0f", value.rounded())
    }
}

final class AISpendStore: ObservableObject {
    @Published var providers: [AIProviderBudget] {
        didSet { persist() }
    }
    
    private static let storageKey = "jarvisAISpendBudgets.v1"
    
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([AIProviderBudget].self, from: data),
           !decoded.isEmpty {
            providers = decoded
        } else {
            providers = Self.defaults
        }
    }
    
    var activeProviders: [AIProviderBudget] {
        providers.filter(\.enabled)
    }
    
    var totalSpent: Double {
        activeProviders.reduce(0) { $0 + $1.spent }
    }
    
    var totalLimit: Double {
        activeProviders.reduce(0) { $0 + $1.limit }
    }
    
    var totalRatio: Double {
        guard totalLimit > 0 else { return 0 }
        return min(1, totalSpent / totalLimit)
    }
    
    func updateSpent(id: String, to value: Double) {
        guard let idx = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[idx].spent = max(0, value)
    }
    
    func bumpSpent(id: String, by delta: Double) {
        guard let idx = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[idx].spent = max(0, providers[idx].spent + delta)
    }
    
    func updateLimit(id: String, to value: Double) {
        guard let idx = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[idx].limit = max(1, value)
    }
    
    func openBilling(for provider: AIProviderBudget) {
        guard let url = URL(string: provider.billingURL) else { return }
        NSWorkspace.shared.open(url)
    }
    
    func resetCycle() {
        for i in providers.indices {
            providers[i].spent = 0
        }
    }
    
    private func persist() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    
    static let defaults: [AIProviderBudget] = [
        AIProviderBudget(
            id: "cursor",
            name: "Cursor",
            spent: 0,
            limit: 60,
            accentHex: "#22D3EE",
            billingURL: "https://cursor.com/dashboard?tab=billing",
            enabled: true
        ),
        AIProviderBudget(
            id: "claude",
            name: "Claude",
            spent: 0,
            limit: 50,
            accentHex: "#D4A574",
            billingURL: "https://console.anthropic.com/settings/billing",
            enabled: true
        ),
        AIProviderBudget(
            id: "minimax",
            name: "MiniMax",
            spent: 0,
            limit: 40,
            accentHex: "#A78BFA",
            billingURL: "https://platform.minimaxi.com/",
            enabled: true
        ),
        AIProviderBudget(
            id: "antigravity",
            name: "Antigravity",
            spent: 0,
            limit: 30,
            accentHex: "#34D399",
            billingURL: "https://www.google.com/search?q=antigravity+ai+billing",
            enabled: true
        ),
        AIProviderBudget(
            id: "chatgpt",
            name: "ChatGPT",
            spent: 0,
            limit: 40,
            accentHex: "#10B981",
            billingURL: "https://platform.openai.com/usage",
            enabled: true
        ),
        AIProviderBudget(
            id: "gemini",
            name: "Gemini",
            spent: 0,
            limit: 25,
            accentHex: "#60A5FA",
            billingURL: "https://aistudio.google.com/",
            enabled: false
        )
    ]
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct AISpendWidget: View {
    @ObservedObject var store: AISpendStore
    @State private var editingId: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.cyan)
                Text("LÍMITES IA")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.6)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(AIProviderBudget.formatMoney(store.totalSpent))/\(AIProviderBudget.formatMoney(store.totalLimit))")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .monospacedDigit()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(3, geo.size.width * store.totalRatio))
                }
            }
            .frame(height: 3)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(store.activeProviders) { provider in
                        providerRow(provider)
                    }
                }
            }
            
            HStack(spacing: 8) {
                Button("Reset") {
                    store.resetCycle()
                    editingId = nil
                }
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(editingId == nil ? "clic = ±$5 · ⌘ clic = billing" : "ajustando…")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(10)
        .frame(width: 150, height: 215)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func providerRow(_ provider: AIProviderBudget) -> some View {
        let isEditing = editingId == provider.id
        
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(provider.accent)
                    .frame(width: 5, height: 5)
                Text(provider.name)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(provider.spentLabel)/\(provider.limitLabel)")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(provider.isOverLimit ? .red.opacity(0.9) : .white.opacity(0.55))
                    .monospacedDigit()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(provider.isOverLimit ? Color.red.opacity(0.85) : provider.accent)
                        .frame(width: max(2, geo.size.width * provider.ratio))
                }
            }
            .frame(height: 3)
            
            if isEditing {
                HStack(spacing: 4) {
                    miniBtn("−") { store.bumpSpent(id: provider.id, by: -5) }
                    miniBtn("+") { store.bumpSpent(id: provider.id, by: 5) }
                    Spacer()
                    miniBtn("L−") { store.updateLimit(id: provider.id, to: provider.limit - 10) }
                    miniBtn("L+") { store.updateLimit(id: provider.id, to: provider.limit + 10) }
                    Button("OK") { editingId = nil }
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.cyan)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                store.openBilling(for: provider)
            } else if editingId == provider.id {
                editingId = nil
            } else {
                editingId = provider.id
            }
        }
    }
    
    private func miniBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
