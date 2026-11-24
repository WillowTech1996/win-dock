import AppKit
import SwiftUI

class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    @Published private(set) var userProfileImage: NSImage?
    @Published private(set) var userName: String = ""

    private var hasLoaded = false

    private init() {
        AppLogger.shared.debug("UserProfileManager initializing - bundle path: \(Bundle.main.bundlePath)")
        loadUserProfile()
    }

    func loadUserProfile() {
        // The profile (image/name) doesn't change during a session and loading it spawns
        // subprocesses, so do the expensive work only once.
        guard !hasLoaded else { return }
        hasLoaded = true

        AppLogger.shared.debug("UserProfileManager.loadUserProfile() called")
        DispatchQueue.global(qos: .background).async {
            let image = self.fetchUserProfileImage()
            let name = self.fetchUserName()
            
            DispatchQueue.main.async {
                self.userProfileImage = image
                self.userName = name
                AppLogger.shared.info("User profile loaded: \(name)")
            }
        }
    }
    
    private func fetchUserProfileImage() -> NSImage? {
        // Method 1: Try to get from System Preferences cache
        if let systemImage = getSystemProfileImage() {
            return systemImage
        }
        
        // Method 2: Try to get from Directory Services
        if let directoryImage = getDirectoryServicesImage() {
            return directoryImage
        }
        
        // Fallback: Return default user icon
        return getDefaultUserIcon()
    }
    
    private func fetchUserName() -> String {
        // Try to get full name from various sources
        
        // Method 1: From NSFullUserName()
        let fullName = NSFullUserName()
        if !fullName.isEmpty && fullName != NSUserName() {
            return fullName
        }
        
        // Method 2: From Directory Services
        if let directoryName = getDirectoryServicesName() {
            return directoryName
        }
        
        // Fallback: Use username
        return NSUserName()
    }
    
    private func getSystemProfileImage() -> NSImage? {
        // Try to get profile image from system preferences cache
        let userImagePaths = [
            "/Library/User Pictures/\(NSUserName()).tif",
            "/Library/User Pictures/\(NSUserName()).png",
            "/Library/User Pictures/\(NSUserName()).jpg",
            "/Library/User Pictures/\(NSUserName()).jpeg",
            "/var/db/dslocal/nodes/Default/users/\(NSUserName()).plist",
        ]
        
        for path in userImagePaths {
            if FileManager.default.fileExists(atPath: path) {
                if let image = NSImage(contentsOfFile: path) {
                    return image
                }
            }
        }
        
        // Try to read from user's directory services record
        let task = Process()
        task.launchPath = "/usr/bin/dscl"
        task.arguments = [".", "-read", "/Users/\(NSUserName())", "JPEGPhoto"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse the JPEG data from the output
            if let jpegData = parseJPEGFromDSCLOutput(output) {
                return NSImage(data: jpegData)
            }
        }
        
        return nil
    }
    
    private func getDirectoryServicesImage() -> NSImage? {
        // SECURITY: Use Process with array arguments instead of shell string interpolation
        // This prevents command injection if username contains shell metacharacters
        
        // First get the raw JPEG photo data using dscl
        let dsclTask = Process()
        dsclTask.launchPath = "/usr/bin/dscl"
        dsclTask.arguments = [".", "-read", "/Users/\(NSUserName())", "JPEGPhoto"]
        
        let dsclPipe = Pipe()
        dsclTask.standardOutput = dsclPipe
        dsclTask.launch()
        let dsclData = dsclPipe.fileHandleForReading.readDataToEndOfFile()
        dsclTask.waitUntilExit()
        
        guard dsclTask.terminationStatus == 0 else {
            return nil
        }
        
        guard let dsclOutput = String(data: dsclData, encoding: .utf8) else {
            return nil
        }
        
        // Extract the hex string (skip the "JPEGPhoto:" line)
        let lines = dsclOutput.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            return nil
        }
        
        let hexString = String(lines[1...].joined().filter { $0.isHexDigit })
        
        guard let imageData = Data(fromHexString: hexString), imageData.count > 0 else {
            return nil
        }
        
        return NSImage(data: imageData)
    }
    
    private func getDirectoryServicesName() -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/dscl"
        task.arguments = [".", "-read", "/Users/\(NSUserName())", "RealName"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse the real name from the output
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("RealName:") {
                    let name = line.replacingOccurrences(of: "RealName:", with: "").trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        return name
                    }
                }
            }
        }
        
        return nil
    }
    
    private func parseJPEGFromDSCLOutput(_ output: String) -> Data? {
        // Parse hex-encoded JPEG data from dscl output
        let lines = output.components(separatedBy: .newlines)
        var hexString = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.allSatisfy({ $0.isHexDigit || $0 == " " }) {
                hexString += trimmed.replacingOccurrences(of: " ", with: "")
            }
        }
        
        if !hexString.isEmpty {
            return Data(fromHexString: hexString)
        }
        
        return nil
    }
    
    private func getDefaultUserIcon() -> NSImage? {
        // Return a nice default user icon
        if let systemIcon = NSImage(named: "NSUser") {
            return systemIcon
        }
        
        // Create a custom default user icon
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw a circle with user icon
        let rect = NSRect(origin: .zero, size: size)
        let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
        
        NSColor.systemBlue.setFill()
        circlePath.fill()
        
        // Draw a simple user silhouette
        NSColor.white.setFill()
        let headRect = NSRect(x: 22, y: 36, width: 20, height: 20)
        let headPath = NSBezierPath(ovalIn: headRect)
        headPath.fill()
        
        let bodyRect = NSRect(x: 16, y: 8, width: 32, height: 32)
        let bodyPath = NSBezierPath(ovalIn: bodyRect)
        bodyPath.fill()
        
        image.unlockFocus()
        return image
    }
}

extension Data {
    init?(fromHexString hex: String) {
        let len = hex.count
        if len % 2 != 0 { return nil }
        
        var data = Data()
        var index = hex.startIndex
        
        for _ in 0..<len/2 {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = String(hex[index..<nextIndex])
            
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            
            index = nextIndex
        }
        
        self = data
    }
}
