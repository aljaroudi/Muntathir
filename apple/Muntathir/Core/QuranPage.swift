import Foundation
import SQLite3

/// One page of the 15-line Madani mushaf. Words are QPC Hafs text for the KFGQPC font; `verses` keep the Tanzil text that highlights refer to.
struct QuranPage: Sendable {
    struct Word: Identifiable, Sendable {
        let index: Int
        let word: Int
        let text: String
        var id: String { "\(index):\(word)" }
    }

    struct Line: Identifiable, Sendable {
        enum Kind: String, Sendable { case ayah, surahName = "surah_name", basmallah }
        let number: Int
        let kind: Kind
        let centered: Bool
        let surah: Int
        var words: [Word] = []
        var id: Int { number }
    }

    static let count = 604

    let number: Int
    let lines: [Line]
    let verses: [Int: Ayah]
    let juz: Int
    let hizbQuarter: Int
    let sajdas: Set<Int>

    var surah: Int { lines.first { $0.kind == .ayah }?.surah ?? lines.first?.surah ?? 1 }
}

extension QuranDatabase {
    func page(_ number: Int) throws -> QuranPage {
        let connection = try connection()
        var lines = try connection.query("SELECT line, type, centered, sura, first_index, first_word, last_index, last_word FROM quran_lines WHERE page = ? ORDER BY line", parameters: [String(number)]) { row in
            (QuranPage.Line(number: Int(sqlite3_column_int(row, 0)), kind: QuranPage.Line.Kind(rawValue: QuranConnection.text(row, 1)) ?? .ayah,
                            centered: sqlite3_column_int(row, 2) != 0, surah: Int(sqlite3_column_int(row, 3))),
             (Int(sqlite3_column_int(row, 4)), Int(sqlite3_column_int(row, 5))), (Int(sqlite3_column_int(row, 6)), Int(sqlite3_column_int(row, 7))))
        }
        let ranges = lines.filter { $0.0.kind == .ayah }
        guard let first = ranges.first?.1, let last = ranges.last?.2 else { throw QuranDatabaseError.unavailable }
        let words = try connection.query("SELECT \"index\", word, text FROM quran_words_qpc WHERE (\"index\", word) BETWEEN (?, ?) AND (?, ?) ORDER BY \"index\", word",
                                         parameters: [first.0, first.1, last.0, last.1].map(String.init)) { row in
            QuranPage.Word(index: Int(sqlite3_column_int(row, 0)), word: Int(sqlite3_column_int(row, 1)), text: QuranConnection.text(row, 2))
        }
        for offset in lines.indices where lines[offset].0.kind == .ayah {
            let (start, end) = (lines[offset].1, lines[offset].2)
            lines[offset].0.words = words.filter { ($0.index, $0.word) >= start && ($0.index, $0.word) <= end }
        }
        let bounds = [String(first.0), String(last.0)]
        let verses = try readVerses(where: "\"index\" BETWEEN ? AND ?", parameters: bounds)
        func division(_ kind: String) throws -> Int {
            try connection.query("SELECT max(number) FROM quran_divisions WHERE kind = ? AND start <= ?", parameters: [kind, String(last.0)]) { Int(sqlite3_column_int($0, 0)) }.first ?? 1
        }
        return try QuranPage(number: number, lines: lines.map(\.0), verses: Dictionary(uniqueKeysWithValues: verses),
                             juz: division("juz"), hizbQuarter: division("hizb"),
                             sajdas: Set(connection.query("SELECT start FROM quran_sajdas WHERE start BETWEEN ? AND ?", parameters: bounds) { Int(sqlite3_column_int($0, 0)) }))
    }

    func page(surah: Int, verse: Int) throws -> Int? {
        try connection().query("SELECT page FROM quran WHERE sura = ? AND aya = ?", parameters: [String(surah), String(verse)]) { Int(sqlite3_column_int($0, 0)) }.first
    }
}
