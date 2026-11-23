import Foundation

struct ProjectFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String

    func projects(in library: [Project], clientID: UUID) -> [Project] {
        library.filter { $0.estimate.clientID == clientID && $0.estimate.folderID == id }
    }
}

extension Client {
    func folder(_ id: UUID?) -> ProjectFolder? {
        guard let id else { return nil }
        return projectFolders?.first { $0.id == id }
    }

    mutating func saveFolder(_ folder: ProjectFolder) throws {
        var updated = folder
        updated.name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { throw LibraryError(description: "Enter a folder name.") }
        var folders = projectFolders ?? []
        guard !folders.contains(where: { $0.id != updated.id && $0.name.localizedCaseInsensitiveCompare(updated.name) == .orderedSame }) else {
            throw LibraryError(description: "That client already has a folder with this name.")
        }
        if let index = folders.firstIndex(where: { $0.id == updated.id }) {
            folders[index] = updated
        } else {
            folders.append(updated)
        }
        projectFolders = folders
    }
}
