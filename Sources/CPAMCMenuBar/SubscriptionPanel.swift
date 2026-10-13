import AppKit
import SwiftUI
import QuotaCore

struct MenuRow: View {
    let title: String
    var hoverTitle: String? = nil
    var shortcut: String? = nil
    var disabled = false
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(hovered ? hoverTitle ?? title : title).lineLimit(1)
                Spacer(minLength: 8)
                if let shortcut { Text(shortcut).foregroundStyle(hovered ? Color.white.opacity(0.8) : .secondary) }
            }
            .padding(.horizontal, 10).frame(height: 23)
            .contentShape(Rectangle())
            .foregroundStyle(hovered && !disabled ? Color.white : Color.primary)
            .background(hovered && !disabled ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.5 : 1)
        .onHover { hovered = $0 }.accessibilityLabel(title)
    }
}

struct SubscriptionPanel: View {
    @ObservedObject var store: QuotaStore
    @AppStorage("hideAccountNames") private var hideNames = false
    @AppStorage("language") private var language = "auto"
    @State private var selected: String?
    @State private var settings = false
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            if settings {
                ConnectionSettings(store: store) { settings = false }
            } else if let selected, let account = store.snapshot?.accounts.first(where: { $0.id == selected }) {
                detail(account)
            } else { overview }
        }
        .font(.system(size: 13)).frame(width: 350).padding(5)
        .onAppear { store.start() }
        .onChange(of: language) { _ in }
    }
    private var separator: some View { Divider().padding(.horizontal, 10).padding(.vertical, 5) }
    private func name(_ account: SubscriptionAccount) -> String {
        if !hideNames { return account.label }
        let accounts = store.snapshot?.accounts.filter { $0.provider == account.provider } ?? []
        let ordinal = (accounts.firstIndex(where: { $0.id == account.id }) ?? 0) + 1
        return "\(account.provider.title) \(ordinal)"
    }
    private var overview: some View {
        VStack(spacing: 0) {
            if store.snapshot == nil {
                Text(store.error == nil ? Copy.text("loading") : Copy.text("offline"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            if let snapshot = store.snapshot {
                if snapshot.accounts.isEmpty { Text(Copy.text("empty")).padding(10).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Provider.allCases, id: \.self) { provider in
                            let accounts = snapshot.accounts.filter { $0.provider == provider }
                            if !accounts.isEmpty {
                                let summary = snapshot.summary(provider, at: store.now)
                                HStack {
                                    Text(provider.title).fontWeight(.medium)
                                    if provider == .claude {
                                        Text(Copy.text("barLegend")).font(.system(size: 10))
                                    }
                                    Spacer()
                                    Text("\(summary.readyCount)/\(summary.accountCount) \(Copy.text("ready"))").font(.system(size: 11))
                                }.foregroundStyle(.secondary).padding(.horizontal, 10).frame(height: 25)
                                ForEach(accounts) { account in accountRow(account) }
                                if provider == .codex { separator }
                            }
                        }
                    }
                }.frame(height: min(330, CGFloat(snapshot.accounts.count) * 25 + 70))
            }
            if let error = store.error {
                Text(Copy.isFrench ? Copy.text("unknownError") : error)
                    .font(.system(size: 11)).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            footer
        }
    }
    private func accountRow(_ account: SubscriptionAccount) -> some View {
        let window = account.tightestWindow
        let left = account.disabled ? window?.leftPercent : account.freshLeft(at: store.now)
        let tone = store.error == nil ? account.tone(at: store.now) : .unknown
        let caption = account.disabled ? Copy.text("disabled") + (account.hasUsage ? " · " + Copy.percent(left) : "") : left == nil && window?.leftPercent != nil
            ? Copy.text("lastKnown") + " · " + Copy.percent(window?.leftPercent) : Copy.percent(left)
        let highlighted = hovered == account.id && account.canInspect
        let renewal = Copy.duration(account.cooldownUntil.flatMap { $0 > store.now ? $0 : nil } ?? window?.resetsAt, now: store.now)
        return Button { store.accountUpdateError = nil; selected = account.id } label: {
            HStack(spacing: 10) {
                if account.provider == .claude {
                    HStack(spacing: 3) {
                        quotaBar(account.claudeRowWindows[0], account: account, label: Copy.text("session"))
                        quotaBar(account.claudeRowWindows[1], account: account, label: Copy.text("weekly"))
                    }
                } else {
                    LevelCapsule(left: account.disabled ? left : tone == .unknown ? nil : left, tone: tone)
                }
                Text(name(account) + " · " + (highlighted ? account.plan.map { $0 + " · " } ?? "" : "") + caption)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                if let renewal, !account.disabled { Text(renewal).monospacedDigit().foregroundStyle(highlighted ? .white.opacity(0.8) : .secondary) }
            }
            .padding(.horizontal, 10).frame(height: 25).contentShape(Rectangle())
            .foregroundStyle(highlighted ? Color.white : account.disabled ? .secondary : .primary)
            .background(highlighted ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).disabled(!account.canInspect).onHover { hovered = $0 && account.canInspect ? account.id : nil }
        .help([account.plan, account.readError].compactMap { $0 }.joined(separator: " · "))
        .accessibilityLabel("\(name(account)), \(caption), \(renewal ?? "")")
        .accessibilityValue(account.provider == .claude ? Copy.text("session") + ": " + Copy.percent(account.claudeRowWindows[0]?.leftPercent) + ", " + Copy.text("weekly") + ": " + Copy.percent(account.claudeRowWindows[1]?.leftPercent) : "")
    }
    private func quotaBar(_ window: QuotaWindow?, account: SubscriptionAccount, label: String) -> some View {
        let current = account.readError == nil && store.error == nil && window?.isFresh(at: store.now) == true
        let tone = current && !account.disabled ? window?.tone(at: store.now) ?? .unknown : .unknown
        return LevelCapsule(left: current || account.disabled ? window?.leftPercent : nil, tone: tone)
            .help(label + ": " + Copy.percent(window?.leftPercent))
    }
    private func detail(_ account: SubscriptionAccount) -> some View {
        VStack(spacing: 0) {
            Button { selected = nil } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(name(account)).fontWeight(.medium).lineLimit(1)
                    Spacer()
                    if let plan = account.plan { Text(plan).foregroundStyle(.secondary) }
                }.frame(height: 29).padding(.horizontal, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Copy.text("back"))
            separator
            HStack {
                Text(Copy.text("accountEnabled"))
                Spacer()
                Toggle(Copy.text("accountEnabled"), isOn: Binding(
                    get: { !account.disabled },
                    set: { enabled in Task { await store.setAccountEnabled(account, enabled: enabled) } }
                )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(store.busy || store.accountUpdating != nil)
                if store.accountUpdating == account.id { ProgressView().controlSize(.mini).accessibilityLabel(Copy.text("accountUpdating")) }
            }.padding(.horizontal, 10).padding(.vertical, 4)
            note(Copy.text("accountToggleHint"))
            if let updateError = store.accountUpdateError {
                Text(updateError).font(.system(size: 11)).foregroundStyle(.red)
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            separator
            if account.disabled { note(Copy.text("disabled")) }
            ForEach(account.windows) { window in
                let fresh = window.isFresh(at: store.now) && account.readError == nil && store.error == nil
                let tone = fresh ? window.tone(at: store.now) : .unknown
                HStack(alignment: .top, spacing: 10) {
                    LevelCapsule(left: fresh ? window.leftPercent : nil, tone: tone).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(Copy.text(window.id))
                            Spacer()
                            Text(Copy.percent(window.leftPercent)).foregroundStyle(tone == .out || tone == .low ? tone.color : .primary)
                        }
                        if !fresh { Text(Copy.text("lastKnown")).font(.system(size: 11)).foregroundStyle(.secondary) }
                        if let reset = window.resetsAt {
                            Text(reset > store.now ? Copy.text("renews") + " " + Copy.timestamp(reset, now: store.now, includeDate: true) : Copy.text("awaiting"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.horizontal, 10).padding(.vertical, 6)
            }
            if let cooldown = account.cooldownUntil, cooldown > store.now {
                note(Copy.text("cooldown") + " " + Copy.timestamp(cooldown, now: store.now, includeDate: true))
            }
            if let error = account.readError { note(Copy.isFrench ? Copy.text("unknownError") : error) }
            if let extra = account.extraUsageEnabled { note(Copy.text(extra ? "extraOn" : "extraOff")) }
            if account.unlimitedCredits { note(Copy.text("credits") + ": " + Copy.text("unlimited")) }
            else if let credits = account.paidCredits { note(Copy.text("credits") + ": " + credits.formatted(.number.precision(.fractionLength(0...2)))) }
            if let grants = account.resetGrantsLeft, grants > 0 { note(Copy.text("resetGrant") + ": \(grants)") }
            if let checked = account.checkedAt { note(Copy.text("lastChecked") + " " + Copy.timestamp(checked, now: store.now)) }
            footer
        }
    }
    private func note(_ title: String) -> some View {
        Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 3)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            separator
            MenuRow(title: store.busy ? Copy.text("refreshing") : store.snapshot.map {
                Copy.text("updated") + " " + Copy.timestamp($0.fetchedAt, now: store.now)
            } ?? Copy.text("refresh"), hoverTitle: Copy.text("refresh"), shortcut: "⌘R", disabled: store.busy) {
                Task { await store.refresh(force: true) }
            }.keyboardShortcut("r", modifiers: .command)
            MenuRow(title: Copy.text("dashboard")) { store.openDashboard() }
            MenuRow(title: Copy.text("settings"), shortcut: "⌘,") { settings = true }.keyboardShortcut(",", modifiers: .command)
            separator
            MenuRow(title: Copy.text("quit"), shortcut: "⌘Q") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            if store.demo {
                Text(Copy.text("demo")).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.vertical, 5)
            }
        }
    }
}
