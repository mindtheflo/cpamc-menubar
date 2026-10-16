import AppKit

let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let candidates = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int) == pid &&
    (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 50
}
let selected = candidates.max {
    (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) <
    (($1[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0)
}
let output = try JSONSerialization.data(withJSONObject: selected.map { [$0] } ?? [])
print(String(data: output, encoding: .utf8)!)
