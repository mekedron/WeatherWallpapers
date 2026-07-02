import Foundation

/// A target device with its native screen resolution in pixels.
struct DeviceSpec: Codable, Hashable, Identifiable {
    enum Category: String, Codable, CaseIterable, Identifiable {
        case iphone
        case ipad
        case mac
        case custom

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .iphone: return "iPhone"
            case .ipad: return "iPad"
            case .mac: return "Mac"
            case .custom: return String(localized: "Custom")
            }
        }
    }

    var name: String
    var width: Int
    var height: Int
    var category: Category

    var id: String { "\(name)_\(width)x\(height)" }

    var resolutionText: String { "\(width) × \(height)" }

    var pixelSize: CGSize { CGSize(width: width, height: height) }

    static let builtIn: [DeviceSpec] = [
        // iPhones (portrait, native pixels)
        DeviceSpec(name: "iPhone 17 Pro Max / 16 Pro Max", width: 1320, height: 2868, category: .iphone),
        DeviceSpec(name: "iPhone 17 Pro / 17 / 16 Pro", width: 1206, height: 2622, category: .iphone),
        DeviceSpec(name: "iPhone Air", width: 1260, height: 2736, category: .iphone),
        DeviceSpec(name: "iPhone 16 Plus / 15 Plus / 15 Pro Max / 14 Pro Max", width: 1290, height: 2796, category: .iphone),
        DeviceSpec(name: "iPhone 16 / 16e / 15 / 15 Pro / 14 Pro", width: 1179, height: 2556, category: .iphone),
        DeviceSpec(name: "iPhone 14 / 13 / 13 Pro / 12 / 12 Pro", width: 1170, height: 2532, category: .iphone),
        DeviceSpec(name: "iPhone 14 Plus / 13 Pro Max / 12 Pro Max", width: 1284, height: 2778, category: .iphone),
        DeviceSpec(name: "iPhone 13 mini / 12 mini", width: 1080, height: 2340, category: .iphone),
        DeviceSpec(name: "iPhone 11 Pro Max / XS Max", width: 1242, height: 2688, category: .iphone),
        DeviceSpec(name: "iPhone 11 Pro / XS / X", width: 1125, height: 2436, category: .iphone),
        DeviceSpec(name: "iPhone 11 / XR", width: 828, height: 1792, category: .iphone),
        DeviceSpec(name: "iPhone SE (3rd gen)", width: 750, height: 1334, category: .iphone),
        // iPads (portrait, native pixels)
        DeviceSpec(name: "iPad Pro 13\" (M4/M5)", width: 2064, height: 2752, category: .ipad),
        DeviceSpec(name: "iPad Pro 12.9\" / Air 13\"", width: 2048, height: 2732, category: .ipad),
        DeviceSpec(name: "iPad Pro 11\" (M4/M5)", width: 1668, height: 2420, category: .ipad),
        DeviceSpec(name: "iPad Air 11\" / Pro 11\" (older)", width: 1668, height: 2388, category: .ipad),
        DeviceSpec(name: "iPad (10th/11th gen)", width: 1640, height: 2360, category: .ipad),
        DeviceSpec(name: "iPad mini (A17 Pro / 6th gen)", width: 1488, height: 2266, category: .ipad),
        // Macs (landscape, native pixels)
        DeviceSpec(name: "MacBook Air 13\" (M2–M4)", width: 2560, height: 1664, category: .mac),
        DeviceSpec(name: "MacBook Air 15\"", width: 2880, height: 1864, category: .mac),
        DeviceSpec(name: "MacBook Pro 14\"", width: 3024, height: 1964, category: .mac),
        DeviceSpec(name: "MacBook Pro 16\"", width: 3456, height: 2234, category: .mac),
        DeviceSpec(name: "MacBook Pro 13\" (Retina)", width: 2560, height: 1600, category: .mac),
        DeviceSpec(name: "iMac 24\"", width: 4480, height: 2520, category: .mac),
        DeviceSpec(name: "Studio Display / iMac 27\"", width: 5120, height: 2880, category: .mac),
    ]
}
