// Prints the window id, bounds and pid of the DevEco emulator window, then
// brings it to the front so screencapture can record live frames.
// Usage: emulator-window (no args). Output: "<windowId> <x> <y> <w> <h> <pid>"
import AppKit
import CoreGraphics
import Foundation

let wanted = CommandLine.arguments.dropFirst().first ?? "Emulator"

guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
  FileHandle.standardError.write("cannot list windows\n".data(using: .utf8)!)
  exit(1)
}

for w in list {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let name = w[kCGWindowName as String] as? String ?? ""
  let layer = w[kCGWindowLayer as String] as? Int ?? -1
  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
  guard owner == wanted, name == wanted, layer == 0,
        let id = w[kCGWindowNumber as String] as? Int,
        let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
        width > 200
  else { continue }
  if let pid = w[kCGWindowOwnerPID as String] as? Int32,
     let app = NSRunningApplication(processIdentifier: pid) {
    _ = app.activate(options: [.activateAllWindows])
    // Wait until the emulator really is frontmost: an occluded window records black.
    for _ in 0..<40 {
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
      usleep(150_000)
    }
    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
    FileHandle.standardError.write("frontmost: \(front)\n".data(using: .utf8)!)
  }
  print("\(id) \(Int(x)) \(Int(y)) \(Int(width)) \(Int(height)) \(w[kCGWindowOwnerPID as String] as? Int ?? 0)")
  exit(0)
}

FileHandle.standardError.write("emulator window not found\n".data(using: .utf8)!)
exit(2)
