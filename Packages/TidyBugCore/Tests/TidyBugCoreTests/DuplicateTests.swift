import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TidyBugCore

@Suite(.timeLimit(.minutes(1))) struct DuplicateFinderTests {
    private func write(_ sb: Sandbox, _ rel: String, seed: UInt8, count: Int = 300_000) throws -> URL {
        let url = sb.root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: count)
        for i in bytes.indices { bytes[i] = UInt8((i * 31 + Int(seed) * 7) & 0xFF) }
        try Data(bytes).write(to: url)
        return url
    }

    @Test func findsExactDuplicates() throws {
        let sb = try Sandbox()
        try write(sb, "Documents/a.bin", seed: 1)
        try write(sb, "Downloads/a copy.bin", seed: 1)
        try write(sb, "Desktop/nested/a.bin", seed: 1)
        try write(sb, "Documents/unique.bin", seed: 9)
        let groups = DuplicateFinder.scan(roots: [sb.root.path], minimumSize: 100_000, guard: sb.guardRail)
        #expect(groups.count == 1)
        #expect(groups.first?.files.count == 3)
        #expect(groups.first?.wasted == 600_000)
    }

    @Test func hardlinksAreNotDuplicates() throws {
        let sb = try Sandbox()
        let a = try write(sb, "Documents/a.bin", seed: 2)
        try FileManager.default.linkItem(at: a, to: sb.root.appendingPathComponent("Documents/b.bin"))
        let groups = DuplicateFinder.scan(roots: [sb.root.path], minimumSize: 100_000, guard: sb.guardRail)
        #expect(groups.isEmpty)
    }

    @Test func sameSizeDifferentContentNotGrouped() throws {
        let sb = try Sandbox()
        try write(sb, "Documents/a.bin", seed: 3)
        let b = try write(sb, "Documents/b.bin", seed: 3)
        // Same size, same head and tail, different middle byte → only full hash can tell.
        var data = try Data(contentsOf: b)
        data[150_000] ^= 0xFF
        try data.write(to: b)
        let groups = DuplicateFinder.scan(roots: [sb.root.path], minimumSize: 100_000, guard: sb.guardRail)
        #expect(groups.isEmpty)
    }

    @Test func keeperPrefersOriginalOutsideDownloads() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let files = [
            DuplicateFile(url: URL(fileURLWithPath: "/u/Downloads/report.pdf"), size: 1, modified: old, autoSelectable: true),
            DuplicateFile(url: URL(fileURLWithPath: "/u/Documents/Work/report.pdf"), size: 1, modified: new, autoSelectable: true),
            DuplicateFile(url: URL(fileURLWithPath: "/u/Documents/report.pdf"), size: 1, modified: new, autoSelectable: true),
        ]
        #expect(DuplicateFinder.chooseKeeper(files).url.path == "/u/Documents/report.pdf")
    }

    @Test func skipsGitAndNodeModules() throws {
        let sb = try Sandbox()
        try write(sb, "Documents/proj/.git/objects/x", seed: 4)
        try write(sb, "Documents/proj/node_modules/y", seed: 4)
        try write(sb, "Documents/z.bin", seed: 4)
        let groups = DuplicateFinder.scan(roots: [sb.root.path], minimumSize: 100_000, guard: sb.guardRail)
        #expect(groups.isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1))) struct SimilarImageTests {
    /// Draws a scene (gradient + shapes) so Vision has real structure to compare.
    private func makeImage(width: Int, height: Int, variant: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let w = CGFloat(width), h = CGFloat(height)
        if variant == 2 {
            // A completely different picture: stripes.
            for i in 0..<12 {
                ctx.setFillColor(CGColor(red: i % 2 == 0 ? 0.1 : 0.9, green: 0.2, blue: CGFloat(i) / 12, alpha: 1))
                ctx.fill(CGRect(x: CGFloat(i) * w / 12, y: 0, width: w / 12, height: h))
            }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: w * 0.1, y: h * 0.6, width: w * 0.8, height: h * 0.1))
            return ctx.makeImage()!
        }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h * 0.4, width: w, height: h * 0.6))       // sky
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.4))              // grass
        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: w * 0.65, y: h * 0.62, width: w * 0.2, height: w * 0.2)) // sun
        ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: w * 0.2, y: h * 0.25, width: w * 0.25, height: h * 0.25))            // house
        if variant == 1 {
            // Slight edit: a small bird.
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: w * 0.4, y: h * 0.8, width: w * 0.02, height: w * 0.01))
        }
        return ctx.makeImage()!
    }

    private func save(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.9) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test func clustersNearIdenticalPhotos() async throws {
        let sb = try Sandbox()
        let dir = sb.root.appendingPathComponent("Pictures")
        try save(makeImage(width: 1600, height: 1200, variant: 0), to: dir.appendingPathComponent("original.png"), type: .png)
        try save(makeImage(width: 800, height: 600, variant: 1), to: dir.appendingPathComponent("resized.jpg"), type: .jpeg, quality: 0.6)
        try save(makeImage(width: 1600, height: 1200, variant: 2), to: dir.appendingPathComponent("other.png"), type: .png)

        let clusters = await SimilarImageFinder.scan(roots: [dir.path], minimumSize: 1,
                                                     threshold: SimilarImageFinder.threshold(strictness: 0.5), guard: sb.guardRail)
        #expect(clusters.count == 1)
        let names = Set(clusters.first?.photos.map(\.name) ?? [])
        #expect(names == ["original.png", "resized.jpg"])
        #expect(clusters.first?.keeper.name == "original.png", "highest resolution wins")
    }

    @Test func strictModeSeparatesEditedCopy() async throws {
        let sb = try Sandbox()
        let dir = sb.root.appendingPathComponent("Pictures")
        try save(makeImage(width: 1600, height: 1200, variant: 0), to: dir.appendingPathComponent("a.png"), type: .png)
        try save(makeImage(width: 800, height: 600, variant: 1), to: dir.appendingPathComponent("b.jpg"), type: .jpeg, quality: 0.6)
        let strict = await SimilarImageFinder.scan(roots: [dir.path], minimumSize: 1,
                                                   threshold: SimilarImageFinder.threshold(strictness: 1), guard: sb.guardRail)
        #expect(strict.isEmpty, "an edited + resized copy is not 'identical'")
    }

    @Test func keeperPrefersResolutionThenSize() {
        let d = Date()
        let a = SimilarPhoto(url: URL(fileURLWithPath: "/a.jpg"), size: 900, modified: d, pixelWidth: 100, pixelHeight: 100)
        let b = SimilarPhoto(url: URL(fileURLWithPath: "/b.jpg"), size: 100, modified: d, pixelWidth: 200, pixelHeight: 200)
        let c = SimilarPhoto(url: URL(fileURLWithPath: "/c.jpg"), size: 500, modified: d, pixelWidth: 200, pixelHeight: 200)
        #expect(SimilarImageFinder.chooseKeeper([a, b, c]).name == "c.jpg")
    }
}
