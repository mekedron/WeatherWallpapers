import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Platform {
    static func revealInFinder(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}

#if os(macOS)
/// Exposes the hosting NSWindow to SwiftUI (e.g. to scope event monitors).
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { window = nsView.window }
    }
}
#endif

enum ImageUtil {
    /// Loads a downsampled image without decoding the full-size bitmap.
    static func downsampled(at url: URL, maxPixel: CGFloat) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    static func downsampled(data: Data, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    static func fileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let utType = UTType(type),
              let ext = utType.preferredFilenameExtension
        else { return "png" }
        return ext
    }

    /// Actual MIME type of image data — providers reject payloads whose
    /// declared type doesn't match the bytes.
    static func mimeType(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let utType = UTType(type),
              let mime = utType.preferredMIMEType
        else { return "image/png" }
        return mime
    }

    /// Storage format for generated wallpapers (Settings → Generation).
    static let formatDefaultsKey = "wallpaperImageFormat"
    /// Whether provider output is upscaled to the device resolution.
    static let upscaleDefaultsKey = "upscaleToDeviceSize"

    static var upscaleEnabled: Bool {
        UserDefaults.standard.object(forKey: upscaleDefaultsKey) as? Bool ?? true
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Prepares provider output for storage:
    /// 1. optionally upscales to the exact device resolution (providers top
    ///    out around 1.5 MP — far below a MacBook screen) using Lanczos plus
    ///    a subtle sharpen, center-cropped to the exact target;
    /// 2. re-encodes as HEIC (~5–8× smaller) unless PNG is selected.
    /// Falls back to the original data if anything goes wrong.
    static func processForStorage(_ data: Data, targetSize: CGSize?) -> (data: Data, fileExtension: String) {
        let format = UserDefaults.standard.string(forKey: formatDefaultsKey) ?? "heic"

        guard
            let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            var image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return (data, fileExtension(for: data)) }

        var changedPixels = false
        if upscaleEnabled, let targetSize, targetSize.width > 1, targetSize.height > 1,
           let upscaled = upscaled(image, to: targetSize) {
            image = upscaled
            changedPixels = true
        }

        let type: UTType = format == "heic" ? .heic : .png
        let quality: CFNumber? = format == "heic" ? 0.85 as CFNumber : nil
        if format != "heic" && !changedPixels {
            // Nothing to do — keep the provider's bytes untouched.
            return (data, fileExtension(for: data))
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil
        ) else { return (data, fileExtension(for: data)) }

        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            return (data, fileExtension(for: data))
        }
        return (output as Data, type.preferredFilenameExtension ?? "heic")
    }

    /// Lanczos resample (up or down) + mild sharpen when enlarging,
    /// center-cropped to exactly `target`.
    /// Returns nil when the image is already exactly the target resolution.
    private static func upscaled(_ image: CGImage, to target: CGSize) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width != target.width || height != target.height else { return nil }
        let scale = max(target.width / width, target.height / height)

        var ci = CIImage(cgImage: image)
        if abs(scale - 1) > 0.005 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = ci
            lanczos.scale = Float(scale)
            lanczos.aspectRatio = 1
            ci = lanczos.outputImage ?? ci
        }

        let extent = ci.extent
        let cropOrigin = CGPoint(
            x: (extent.midX - target.width / 2).rounded(),
            y: (extent.midY - target.height / 2).rounded()
        )
        ci = ci.cropped(to: CGRect(origin: cropOrigin, size: target))

        if scale > 1.2 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = ci
            sharpen.sharpness = 0.25
            ci = sharpen.outputImage ?? ci
        }

        return ciContext.createCGImage(ci, from: ci.extent)
    }

    /// Downscales image data so its pixel count fits within the given budget
    /// (used to satisfy AI upscalers' input limits). Returns PNG data.
    static func limited(toMegapixels budget: Double, data: Data) -> Data {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return data }
        let pixels = Double(image.width * image.height)
        let limit = budget * 1_000_000
        guard pixels > limit else { return data }

        let factor = (limit / pixels).squareRoot()
        var ci = CIImage(cgImage: image)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ci
        lanczos.scale = Float(factor)
        lanczos.aspectRatio = 1
        ci = lanczos.outputImage ?? ci
        guard let scaled = ciContext.createCGImage(ci, from: ci.extent) else { return data }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return data }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination), output.length > 0 else { return data }
        return output as Data
    }
}

/// Async thumbnail with an in-memory cache, keyed by path + modification date
/// so regenerated files refresh automatically.
struct ThumbnailView: View {
    let url: URL
    var maxPixel: CGFloat = 500

    @State private var image: CGImage?

    private static let cache = NSCache<NSString, CGImage>()

    private var cacheKey: String {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            .map { String($0.timeIntervalSince1970) } ?? "0"
        return url.path + "|" + mtime + "|" + String(Int(maxPixel))
    }

    var body: some View {
        let key = cacheKey
        // Sized entirely by the parent — the bitmap never drives layout.
        Color.clear
            .overlay {
                if let image {
                    Image(image, scale: 1, label: Text(url.lastPathComponent))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .clipped()
        .task(id: key) {
            if let cached = Self.cache.object(forKey: key as NSString) {
                image = cached
                return
            }
            let targetURL = url
            let pixel = maxPixel
            let loaded = await Task.detached(priority: .utility) {
                ImageUtil.downsampled(at: targetURL, maxPixel: pixel)
            }.value
            if let loaded {
                Self.cache.setObject(loaded, forKey: key as NSString)
            }
            image = loaded
        }
    }
}
