import ArgumentParser
import Foundation

enum TranslitMode: String, ExpressibleByArgument, CaseIterable {
    case off
    case lat
    case cyr
}

struct Transliterator {
    /// Map a Latin single char or digraph to its Cyrillic equivalent.
    private static let latinToCyrillic: [String: String] = [
        "A": "А", "B": "Б", "C": "Ц", "Č": "Ч", "Ć": "Ћ", "D": "Д", "Đ": "Ђ",
        "E": "Е", "F": "Ф", "G": "Г", "H": "Х", "I": "И", "J": "Ј", "K": "К", "L": "Л",
        "M": "М", "N": "Н", "O": "О", "P": "П", "R": "Р", "S": "С",
        "Š": "Ш", "T": "Т", "U": "У", "V": "В", "Z": "З", "Ž": "Ж",
        "a": "а", "b": "б", "c": "ц", "č": "ч", "ć": "ћ", "d": "д", "đ": "ђ",
        "e": "е", "f": "ф", "g": "г", "h": "х", "i": "и", "j": "ј", "k": "к", "l": "л",
        "m": "м", "n": "н", "o": "о", "p": "п", "r": "р", "s": "с",
        "š": "ш", "t": "т", "u": "у", "v": "в", "z": "з", "ž": "ж",
        "DŽ": "Џ", "Dž": "Џ", "dž": "џ", "dŽ": "џ",
        "Dj": "Ђ", "Dj": "Ђ", "dj": "ђ", "dj": "ђ", // lat j
        "Lj": "Љ", "Lj": "Љ", "lj": "љ", "lj": "љ", // lat j
        "Nj": "Њ", "Nj": "Њ", "nj": "њ", "nj": "њ", // lat j
        "DЈ": "Ђ", "Dј": "Ђ", "dј": "ђ", "dЈ": "ђ", // cyr ј
        "LЈ": "Љ", "Lј": "Љ", "lј": "љ", "lЈ": "љ", // cyr ј
        "NЈ": "Њ", "Nј": "Њ", "nј": "њ", "nЈ": "њ", // cyr ј
    ]

    /// Cyrillic chars that have Latin equivalents (for normalizing mixed-script input).
    private static let cyrillicToLatinSingle: [Character: String] = [
        "А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Ђ": "Đ", "Е": "E", "Ж": "Ž",
        "З": "Z", "И": "I", "Ј": "J", "К": "K", "Л": "L", "Љ": "Lj", "М": "M", "Н": "N",
        "Њ": "Nj", "О": "O", "П": "P", "Р": "R", "С": "S", "Т": "T", "Ћ": "Ć", "У": "U",
        "Ф": "F", "Х": "H", "Ц": "C", "Ч": "Č", "Џ": "Dž", "Ш": "Š",
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "ђ": "đ", "е": "e", "ж": "ž",
        "з": "z", "и": "i", "ј": "j", "к": "k", "л": "l", "љ": "lj", "м": "m", "н": "n",
        "њ": "nj", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "ћ": "ć", "у": "u",
        "ф": "f", "х": "h", "ц": "c", "ч": "č", "џ": "dž", "ш": "š",
    ]

    /// Reverse mapping: Cyrillic char → Latin string.
    private static let cyrillicToLatin: [String: String] = {
        var result: [String: String] = [:]
        for (lat, cyr) in latinToCyrillic {
            result[cyr] = lat
        }
        return result
    }()

    static func transliterate(_ text: String, mode: TranslitMode) -> String {
        switch mode {
        case .off: return text
        case .cyr: return toCyrillic(text)
        case .lat: return toLatin(text)
        }
    }

    // MARK: - Latin → Cyrillic

    private static func toCyrillic(_ text: String) -> String {
        // Normalize: convert Cyrillic chars that have Latin equivalents to Latin first.
        // This handles mixed-script input like "дj" → "dj" → "ђ".
        let normalized = text.map { char -> String in
            if let lat = cyrillicToLatinSingle[char] {
                return lat
            }
            return String(char)
        }.joined()

        var result = ""
        var i = normalized.startIndex

        while i < normalized.endIndex {
            let remaining = normalized[i...]

            // Try two-character digraph (matches Python prototype logic)
            if remaining.count >= 2 {
                let twoChar = String(remaining.prefix(2))
                // Step 1: exact match (handles "dž", "Dž", "Lj", etc.)
                if let cyr = latinToCyrillic[twoChar] {
                    result += cyr
                    i = normalized.index(i, offsetBy: 2)
                    continue
                }
                // Step 2: capitalized match (handles "DŽ" → "Dž", "LJ" → "Lj")
                let cap = twoChar.capitalized
                if cap != twoChar, let cyr = latinToCyrillic[cap] {
                    result += cyr
                    i = normalized.index(i, offsetBy: 2)
                    continue
                }
            }

            // Fall back to single character
            let char = String(normalized[i])
            result += latinToCyrillic[char] ?? char
            i = normalized.index(after: i)
        }

        return result
    }

    // MARK: - Cyrillic → Latin

    private static func toLatin(_ text: String) -> String {
        var result = ""
        var i = text.startIndex

        while i < text.endIndex {
            // Cyrillic chars that map to Latin digraphs (Љ, Њ, Џ, љ, њ, џ) are single
            // Unicode code points — no need for multi-char detection on input side.
            let char = String(text[i])
            result += cyrillicToLatin[char] ?? char
            i = text.index(after: i)
        }

        return result
    }
}
