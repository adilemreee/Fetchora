import SwiftUI
import QuickLookUI

struct FilePreviewView: View {
    let item: DownloadItem

    @State private var thumbnailImage: NSImage?

    private var fileURL: URL {
        URL(fileURLWithPath: item.destinationPath)
    }

    private var isPreviewable: Bool {
        item.status == .completed &&
        (item.category == .image || item.category == .video)
    }

    var body: some View {
        Group {
            if isPreviewable, let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            } else if item.status == .completed {
                // File type icon
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.destinationPath))
                        .resizable()
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(2)
                        Text(item.totalBytes.formattedFileSize)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard isPreviewable else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: fileURL) {
                let thumbnail = image.resized(to: NSSize(width: 300, height: 200))
                DispatchQueue.main.async {
                    thumbnailImage = thumbnail
                }
            }
        }
    }
}

extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage {
        let ratioW = targetSize.width / size.width
        let ratioH = targetSize.height / size.height
        let ratio = min(ratioW, ratioH)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        return newImage
    }
}
