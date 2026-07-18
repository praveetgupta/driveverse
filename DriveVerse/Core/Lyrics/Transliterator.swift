import Foundation

/// Romanizes lyric text so every language displays in Latin ("English")
/// letters — Devanagari (Hindi), Gurmukhi, Cyrillic, kana, Hangul, etc. —
/// using the ICU transforms built into Foundation: fully offline, no
/// dependencies. Pure-Latin text passes through untouched so English lyrics
/// (and accents the artist chose, like "Motörhead") are never mangled.
enum Transliterator {
    static func latinized(_ text: String) -> String {
        guard needsLatinization(text) else { return text }
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }

    /// True when the text contains characters from a non-Latin script.
    static func needsLatinization(_ text: String) -> Bool {
        text.range(of: "[^\\p{Latin}\\p{Common}\\p{Inherited}]", options: .regularExpression) != nil
    }
}
