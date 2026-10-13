import Foundation
import QuotaCore

@main
enum QuotaCheck {
    static func main() async {
        do {
            let snapshot = try await ProxyClient(configuration: .load()).fetch(force: true)
            var ordinals: [Provider: Int] = [:]
            let showNames = CommandLine.arguments.contains("--show-names")
            let output: [[String: JSONValue]] = snapshot.accounts.map { account in
                ordinals[account.provider, default: 0] += 1
                return [
                    "account": .string(showNames ? account.label : "\(account.provider.title) \(ordinals[account.provider]!)"),
                    "provider": .string(account.provider.rawValue), "plan": account.plan.map(JSONValue.string) ?? .null,
                    "disabled": .bool(account.disabled), "proxy_unavailable": .bool(account.unavailable),
                    "left_percent": account.freshLeft(at: snapshot.fetchedAt).map(JSONValue.number) ?? .null,
                    "cooldown_until": account.cooldownUntil.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                    "read_error": account.readError.map(JSONValue.string) ?? .null,
                    "windows": .array(account.windows.map { .object([
                        "window": .string($0.id), "used_percent": $0.usedPercent.map(JSONValue.number) ?? .null,
                        "resets_at": $0.resetsAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                    ]) }),
                ]
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
            if snapshot.accounts.contains(where: { !$0.disabled && $0.readError != nil }) { exit(2) }
        } catch {
            let safe = (error as? ProxyError)?.localizedDescription ?? ProxyError.unavailable.localizedDescription
            FileHandle.standardError.write(Data((safe + "\n").utf8)); exit(1)
        }
    }
}
