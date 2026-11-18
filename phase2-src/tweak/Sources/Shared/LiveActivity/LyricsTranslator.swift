// On-device lyrics translation, the same mechanism Dynamic Lyrics uses: Apple's Translation
// framework. The lyric sources bring their own line (and, rarely, a translation), so this runs only
// when the Lyrics page asks for a specific language and a source has none — the line is translated
// on the device, no key, no network beyond the language model download.
//
// Threading: the only shared state is `cache`, touched exclusively on `queue`. A session is created
// per request and never shared, so there is no cross-thread access to TranslationSession.
import Foundation
import Translation

@objc(SGLyricsTranslator)
public final class SGLyricsTranslator: NSObject {
    private static let queue = DispatchQueue(label: "spotifyglass.translation", qos: .userInitiated)
    // A small cache so a line replayed after a seek is not translated again. Touched only on `queue`.
    private static var cache: [String: String] = [:]
    private static let cacheLimit = 512

    /// Translates `text` into the language `languageCode` (e.g. "zh-Hans"), calling `completion` on
    /// an arbitrary queue. A failure calls back with nil; the caller keeps the original line.
    @objc public static func translate(_ text: String, to languageCode: String, completion: @escaping (String?) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, languageCode.count >= 2 else {
            completion(nil)
            return
        }
        guard #available(iOS 26.0, *) else {
            completion(nil)
            return
        }
        let key = "\(languageCode)\u{1f}\(trimmed)"
        queue.async {
            if let hit = cache[key] {
                completion(hit)
                return
            }
            Task {
                do {
                    // Most lyric sources sing in English; the engine still detects each line's real
                    // source language. The model is downloaded on the first prepareTranslation call
                    // and kept by the system afterwards.
                    let session = TranslationSession(
                        installedSource: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: languageCode))
                    try await session.prepareTranslation()
                    let responses = try await session.translations(from: [
                        TranslationSession.Request(sourceText: trimmed)
                    ])
                    guard let translated = responses.first?.targetText, !translated.isEmpty else {
                        completion(nil)
                        return
                    }
                    queue.async {
                        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
                        cache[key] = translated
                    }
                    completion(translated)
                } catch {
                    completion(nil)
                }
            }
        }
    }
}
