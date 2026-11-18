// On-device lyrics translation, the same mechanism Dynamic Lyrics uses: Apple's Translation
// framework. The lyric sources bring their own line (and, rarely, a translation), so this runs only
// when the Lyrics page asks for a specific language and a source has none — the line is translated
// on the device, no key, no network beyond the language model download.
import Foundation
import Translation

@objc(SGLyricsTranslator)
public final class SGLyricsTranslator: NSObject {
    private static let queue = DispatchQueue(label: "spotifyglass.translation", qos: .userInitiated)
    // One prepared session per target language, kept so the downloaded model stays warm.
    @available(iOS 18.0, *)
    private static var sessions: [String: TranslationSession] = [:]
    // A small cache so a line replayed after a seek is not translated again.
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
                    let session = try await session(for: languageCode)
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

    // The session for a target language, prepared (its model downloaded) on first use. Sessions are
    // touched only on `queue`; the async work inside reads the captured session, never the dict.
    @available(iOS 26.0, *)
    private static func session(for languageCode: String) async throws -> TranslationSession {
        if let existing = sessions[languageCode] {
            return existing
        }
        // Most lyric sources sing in English; the engine still detects each line's real source.
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: languageCode))
        try await session.prepareTranslation()
        queue.async {
            sessions[languageCode] = session
        }
        return session
    }
}
