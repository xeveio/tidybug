#if DEBUG
import SwiftUI

/// Dev tool: `TidyBug --render-mascot out.png` renders every mood to a PNG.
@MainActor
enum MascotSnapshot {
    static func render(to path: String) {
        let moods: [MascotMood] = [.idle, .happy, .curious, .scanning, .sweeping, .celebrating, .worried, .sleeping, .waving]
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(240)), count: 3), spacing: 24) {
            ForEach(moods, id: \.self) { mood in
                VStack(spacing: 8) {
                    Tidy(mood: mood, size: 180)
                    Text(String(describing: mood)).font(.display(16)).foregroundStyle(Palette.ink)
                }
            }
        }
        .padding(40)
        .background(Palette.paper)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: grid)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed"); return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
#endif
