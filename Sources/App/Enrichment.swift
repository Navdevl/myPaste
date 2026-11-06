import AppKit
import MyPasteCore
import LinkPresentation
import Vision

/// Background enrichment after capture: OCR for images, metadata for links.
final class Enrichment {
    private let store: ClipStore
    private let prefs: Preferences
    private var providers: [URL: LPMetadataProvider] = [:]
    private var inFlight = Set<Int64>()
    private let ocrQueue = DispatchQueue(label: "mypaste.ocr", qos: .utility)

    init(store: ClipStore, prefs: Preferences) {
        self.store = store
        self.prefs = prefs
    }

    func process(_ item: ClipItem) {
        if item.kind == .image, prefs.ocr, item.ocrText == nil { recognizeText(item) }
        if item.kind == .link, prefs.linkPreviews, !item.linkFetched, !item.isSensitive { fetchLink(item) }
    }

    /// Catch up on items captured while a feature was off, or before a crash.
    func backfill() {
        guard let items = try? store.allItems() else { return }
        for item in items.prefix(200) { process(item) }
    }

    private func recognizeText(_ item: ClipItem) {
        guard let png = store.blob(item, "png") else { return }
        let id = item.id
        ocrQueue.async { [store] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(data: png).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            // Empty string marks "done, nothing found" so backfill doesn't retry.
            DispatchQueue.main.async { try? store.setOCRText(id, text) }
        }
    }

    /// HTML first (Open Graph / <title> / icons), LinkPresentation only if that finds no title.
    private func fetchLink(_ item: ClipItem) {
        guard !inFlight.contains(item.id), let text = item.text,
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            try? store.setLinkPreview(item.id, title: nil, imagePNG: nil)
            return
        }
        let id = item.id
        inFlight.insert(id)
        Task { [weak self] in
            var meta = await Self.scrape(url)
            async let imageData = Self.downloadImage(meta?.imageURL, maxSide: 640)
            // Login-walled pages (404/403 when logged out) still get the site's favicon.
            async let iconData = Self.downloadImage(meta?.iconURL ?? URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL, maxSide: 64)
            var image = await imageData
            let icon = await iconData
            if meta?.title == nil || image == nil, let lp = await self?.linkPresentation(url) {
                meta = meta ?? HTMLMetadata()
                if meta?.title == nil { meta?.title = lp.title }
                if image == nil { image = lp.image }
            }
            await MainActor.run {
                self?.inFlight.remove(id)
                try? self?.store.setLinkPreview(id, title: meta?.title, imagePNG: image, iconPNG: icon)
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            // Some sites serve bots an empty shell; look like Safari.
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
        ]
        return URLSession(configuration: config)
    }()

    private static func scrape(_ url: URL, hops: Int = 3) async -> HTMLMetadata? {
        // One bulk read: AsyncBytes' per-byte iteration took 5–15 s on pages like GitHub's.
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              http.mimeType?.contains("html") ?? true, data.count < 8_000_000 else { return nil }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let final = http.url ?? url
        // "Redirecting…" stub pages (a meta refresh): preview where they lead, not the stub.
        if hops > 0, let next = HTMLMetadata.refreshTarget(html: html, base: final), next != final {
            return await scrape(next, hops: hops - 1) ?? HTMLMetadata.parse(html: html, base: final)
        }
        return HTMLMetadata.parse(html: html, base: final)
    }

    private static func downloadImage(_ url: URL?, maxSide: CGFloat) async -> Data? {
        guard let url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              data.count < 15_000_000, let image = NSImage(data: data) else { return nil }
        return pngThumbnail(image, maxSide: maxSide)
    }

    private func linkPresentation(_ url: URL) async -> (title: String?, image: Data?)? {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                let provider = LPMetadataProvider()
                provider.timeout = 10
                self.providers[url] = provider
                provider.startFetchingMetadata(for: url) { metadata, _ in
                    DispatchQueue.main.async { self.providers[url] = nil }
                    guard let metadata else { return cont.resume(returning: nil) }
                    guard let ip = metadata.imageProvider, ip.canLoadObject(ofClass: NSImage.self) else {
                        return cont.resume(returning: (metadata.title, nil))
                    }
                    ip.loadObject(ofClass: NSImage.self) { obj, _ in
                        cont.resume(returning: (metadata.title, (obj as? NSImage).flatMap { Self.pngThumbnail($0, maxSide: 640) }))
                    }
                }
            }
        }
    }

    static func pngThumbnail(_ image: NSImage, maxSide: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * scale)), h = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}
