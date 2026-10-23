import SwiftUI

struct ContentView: View {
    @StateObject private var browser = FileBrowser()
    @State private var search = ""

    private var visibleItems: [FileItem] {
        search.isEmpty ? browser.items : browser.items.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { browser.goUp() } label: { Image(systemName: "chevron.up") }
                    .disabled(!browser.canGoUp)
                Text(browser.currentURL.path)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                TextField("Cerca", text: $search)
                    .frame(width: 180)
            }
            .padding(8)
            Divider()
            if let message = browser.errorMessage {
                Text(message).foregroundStyle(.red).padding()
            }
            List(visibleItems) { item in
                HStack {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                    Text(item.name)
                    Spacer()
                    if let size = item.size, !item.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if item.isDirectory { browser.open(item.url) }
                    else { NSWorkspace.shared.open(item.url) }
                }
                .contextMenu {
                    Button("Sposta nel Cestino") { browser.moveToTrash(item) }
                }
            }
        }
    }
}
