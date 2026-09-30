import SwiftUI

enum ScanPhase: String {
    case idle, scanning, completed, partial, failed
}

struct ScanSummary {
    let phase: ScanPhase
    let findings: [Finding]
    var reviewCount: Int { findings.filter(\.needsReview).count }
    var title: String {
        if reviewCount > 0 { return "發現 \(reviewCount) 筆待確認線索" }
        switch phase {
        case .idle: return "準備檢查周遭裝置"
        case .scanning: return "正在尋找裝置線索"
        case .completed: return "本輪未發現可疑線索"
        case .partial: return "掃描未完成"
        case .failed: return "目前無法完成掃描"
        }
    }
    var label: String {
        switch phase {
        case .idle: return "尚未開始"
        case .scanning: return "掃描進行中"
        case .completed: return "本輪已結束"
        case .partial: return "僅有部分結果"
        case .failed: return "請檢查連線或權限"
        }
    }
    var symbol: String {
        if reviewCount > 0 { return "exclamationmark.triangle.fill" }
        switch phase {
        case .idle: return "viewfinder"
        case .scanning: return "antenna.radiowaves.left.and.right"
        case .completed: return "magnifyingglass"
        case .partial, .failed: return "exclamationmark.circle.fill"
        }
    }
    var caution: Bool { reviewCount > 0 || phase == .partial || phase == .failed }
}

let reviewAccent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.68, blue: 0.40, alpha: 1)
        : UIColor(red: 0.62, green: 0.23, blue: 0.07, alpha: 1)
})

struct ScanSummaryCard: View {
    let summary: ScanSummary
    let progress: Double
    let status: String
    let source: String
    var accent: Color { summary.caution ? reviewAccent : .accentColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: summary.symbol).font(.system(size: 30, weight: .semibold))
                    .frame(width: 54, height: 54).background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(source + " · " + summary.label).font(.caption.weight(.semibold))
                    Text(summary.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("resultHeadline")
                }
            }.foregroundStyle(accent)
            if summary.phase == .scanning {
                ProgressView(value: progress).tint(accent)
                Text("\(Int(progress * 100))% · 結果持續更新中").font(.caption.monospacedDigit())
            }
            HStack(spacing: 0) {
                metric(summary.reviewCount, "待確認", emphasis: true)
                Divider().frame(height: 42).padding(.horizontal, 16)
                metric(summary.findings.count, "裝置／服務紀錄", emphasis: false)
            }
            Text(status).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scanStatus")
            Label(summary.reviewCount > 0 ? "請檢視命中原因，對照已知家電並人工確認。" : "沒有發現，不代表沒有偷拍設備。", systemImage: "info.circle")
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(summary.caution ? 0.75 : 0.25), lineWidth: summary.caution ? 2 : 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scanSummary")
    }
    private func metric(_ count: Int, _ label: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(emphasis ? accent : .primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
enum ScanFixture {
    static func scenario(for source: Finding.Source) -> String? {
        let args = ProcessInfo.processInfo.arguments
        if source == .network && args.contains("--ui-test-findings") { return "review" }
        guard let index = args.firstIndex(of: "--ui-test-scan"), args.indices.contains(index + 1) else { return nil }
        let parts = args[index + 1].split(separator: ":").map(String.init)
        guard parts.count == 2, parts[0] == (source == .network ? "network" : "bluetooth") else { return nil }
        return parts[1]
    }
    static func findings(_ scenario: String, source: Finding.Source) -> [Finding] {
        guard scenario == "review" || scenario == "ordinary" else { return [] }
        return [Finding(id: "fixture-rtsp", name: scenario == "review" ? "RTSP 測試裝置（模擬）" : "一般裝置（模擬）", source: source,
            address: "192.0.2.10", ports: source == .network && scenario == "review" ? [554] : [],
            reasons: scenario == "review" ? ["模擬測試線索，不是實際偵測結果。"] : [])]
    }
}
#endif
