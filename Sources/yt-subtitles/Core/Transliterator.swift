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
        "A": "А", "B": "Б", "C": "Ц", "Č": "Ч", "Ć": "Ћ", "D": "Д", "Dž": "Џ", "Đ": "Ђ",
        "E": "Е", "F": "Ф", "G": "Г", "H": "Х", "I": "И", "J": "Ј", "K": "К", "L": "Л",
        "Lj": "Љ", "M": "М", "N": "Н", "Nj": "Њ", "O": "О", "P": "П", "R": "Р", "S": "С",
        "Š": "Ш", "T": "Т", "U": "У", "V": "В", "Z": "З", "Ž": "Ж",
        "a": "а", "b": "б", "c": "ц", "č": "ч", "ć": "ћ", "d": "д", "dž": "џ", "đ": "ђ",
        "e": "е", "f": "ф", "g": "г", "h": "х", "i": "и", "j": "ј", "k": "к", "l": "л",
        "lj": "љ", "m": "м", "n": "н", "nj": "њ", "o": "о", "p": "п", "r": "р", "s": "с",
        "š": "ш", "t": "т", "u": "у", "v": "в", "z": "з", "ž": "ж",
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
        var result = ""
        var i = text.startIndex

        while i < text.endIndex {
            let remaining = text[i...]

            // Try two-character digraph (matches Python prototype logic)
            if remaining.count >= 2 {
                let twoChar = String(remaining.prefix(2))
                // Step 1: exact match (handles "dž", "Dž", "Lj", etc.)
                if let cyr = latinToCyrillic[twoChar] {
                    result += cyr
                    i = text.index(i, offsetBy: 2)
                    continue
                }
                // Step 2: capitalized match (handles "DŽ" → "Dž", "LJ" → "Lj")
                let cap = twoChar.capitalized
                if cap != twoChar, let cyr = latinToCyrillic[cap] {
                    result += cyr
                    i = text.index(i, offsetBy: 2)
                    continue
                }
            }

            // Fall back to single character
            let char = String(text[i])
            result += latinToCyrillic[char] ?? char
            i = text.index(after: i)
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
