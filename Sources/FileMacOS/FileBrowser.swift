import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

@MainActor
final class FileBrowser: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published var errorMessage: String?

    init(start: URL = FileManager.default.homeDirectoryForCurrentUser) {
        currentURL = start
        reload()
    }

    var canGoUp: Bool { currentURL.path != "/" }

    func open(_ url: URL) {
        currentURL = url
        reload()
    }

    func goUp() {
        open(currentURL.deletingLastPathComponent())
    }

    func reload() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            items = urls.map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return FileItem(
                    url: url,
                    isDirectory: values?.isDirectory ?? false,
                    size: values?.fileSize.map(Int64.init),
                    modified: values?.contentModificationDate
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }

    func moveToTrash(_ item: FileItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
