import Foundation

enum AccountAuthCoordinator {
    static func syncAuthFile(
        fileManager: FileManager,
        sourcePath: String,
        destinationPath: String,
        destinationDirectory: String? = nil,
        writeFile: (Data, String, Int16) throws -> Void,
        deleteFile: (String) throws -> Void,
        createDirectory: (String, Int16) throws -> Void
    ) throws {
        if let data = fileManager.contents(atPath: sourcePath) {
            if let destinationDirectory {
                try createDirectory(destinationDirectory, 0o700)
            }
            try writeFile(data, destinationPath, 0o600)
        } else {
            try deleteFile(destinationPath)
        }
    }
}
