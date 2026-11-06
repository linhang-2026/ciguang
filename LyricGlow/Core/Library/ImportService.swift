import Foundation

enum ImportError: LocalizedError {
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .copyFailed: return "文件拷贝失败"
        }
    }
}

enum ImportService {
    static var importedDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Imported", isDirectory: true)
    }

    static func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: importedDirectory.path) {
            try FileManager.default.createDirectory(at: importedDirectory, withIntermediateDirectories: true)
        }
    }

        static func copyIntoLibrary(_ sourceURL: URL) throws -> URL {
        try ensureDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let destination = importedDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            throw ImportError.copyFailed
        }
    }
}
