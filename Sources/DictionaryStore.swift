import Foundation
import SQLite3

enum Direction: String, CaseIterable {
    case enFa = "en-fa", faEn = "fa-en", deEn = "de-en"
    case enDe = "en-de", deFa = "de-fa", faDe = "fa-de"

    var title: String {
        switch self {
        case .enFa: "English → Persian"
        case .faEn: "Persian → English"
        case .deEn: "German → English"
        case .enDe: "English → German"
        case .deFa: "German → Persian"
        case .faDe: "Persian → German"
        }
    }
    var sourceLanguage: String {
        switch self {
        case .enFa, .enDe: "en-US"
        case .faEn, .faDe: "fa-IR"
        case .deEn, .deFa: "de-DE"
        }
    }
    var targetsPersian: Bool { self == .enFa || self == .deFa }
    var usesBridge: Bool { self == .deFa || self == .faDe }
}

struct Word: Identifiable, Hashable {
    let id: String
    let english: String
    let level: String
    let ipa: String
    let preview: String
    let direction: Direction
}

struct Sense: Identifiable {
    let id: String
    let partOfSpeech: String
    let definition: String
    let example: String
    let meaning: String
    let persianExample: String
    let bridge: String
}

final class DictionaryStore {
    private let path: String
    init?() {
        guard let url = Bundle.main.url(forResource: "dictionary", withExtension: "sqlite") else { return nil }
        path = url.path
    }
    private func connect() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        return db
    }
    private func str(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: bytes)
    }
    private func prefix(_ query: String) -> String {
        query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }
    private func pairWord(_ statement: OpaquePointer?, _ direction: Direction) -> Word {
        Word(id: "pair:\(sqlite3_column_int64(statement, 0))", english: str(statement, 1),
             level: "", ipa: "", preview: str(statement, 2), direction: direction)
    }
    private func englishWord(_ statement: OpaquePointer?) -> Word {
        Word(id: str(statement, 0), english: str(statement, 1), level: str(statement, 2),
             ipa: str(statement, 3), preview: str(statement, 4), direction: .enFa)
    }

    func search(_ rawQuery: String, direction: Direction) -> [Word] {
        guard let db = connect() else { return [] }
        defer { sqlite3_close(db) }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if direction == .enFa {
            let sql = query.isEmpty ? """
                SELECT w.id,w.english,COALESCE(w.level,''),COALESCE(w.ipa,''),
                  COALESCE((SELECT meaning_fa FROM senses WHERE word_id=w.id ORDER BY sense_order LIMIT 1),'')
                FROM words w ORDER BY COALESCE(w.frequency_rank,999999),w.english LIMIT 100
                """ : """
                SELECT w.id,w.english,COALESCE(w.level,''),COALESCE(w.ipa,''),
                  COALESCE((SELECT meaning_fa FROM senses WHERE word_id=w.id ORDER BY sense_order LIMIT 1),'')
                FROM words w WHERE w.english LIKE ? ESCAPE '\\' COLLATE NOCASE
                  OR w.id IN (SELECT word_id FROM forms WHERE form=? COLLATE NOCASE)
                ORDER BY CASE WHEN w.english=? COLLATE NOCASE THEN 0 ELSE 1 END,
                  COALESCE(w.frequency_rank,999999),w.english LIMIT 100
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            if !query.isEmpty {
                sqlite3_bind_text(statement, 1, prefix(query), -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, query, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, query, -1, SQLITE_TRANSIENT)
            }
            var rows: [Word] = []
            while sqlite3_step(statement) == SQLITE_ROW { rows.append(englishWord(statement)) }
            return rows
        }
        let sql = query.isEmpty
            ? "SELECT id,headword,preview FROM extra_entries WHERE direction=? ORDER BY headword LIMIT 100"
            : "SELECT id,headword,preview FROM extra_entries WHERE direction=? AND headword LIKE ? ESCAPE '\\' COLLATE NOCASE ORDER BY CASE WHEN headword=? COLLATE NOCASE THEN 0 ELSE 1 END,headword LIMIT 100"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, direction.rawValue, -1, SQLITE_TRANSIENT)
        if !query.isEmpty {
            sqlite3_bind_text(statement, 2, prefix(query), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, query, -1, SQLITE_TRANSIENT)
        }
        var rows: [Word] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(pairWord(statement, direction)) }
        return rows
    }

    func senses(for word: Word) -> [Sense] {
        guard let db = connect() else { return [] }
        defer { sqlite3_close(db) }
        if word.direction != .enFa {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT sense_order,meaning,bridge FROM extra_senses WHERE entry_id=? ORDER BY sense_order", -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(word.id.dropFirst(5)) ?? 0)
            var rows: [Sense] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(Sense(id: "\(word.id):\(sqlite3_column_int(statement, 0))", partOfSpeech: "Translation",
                                  definition: "", example: "", meaning: str(statement, 1),
                                  persianExample: "", bridge: str(statement, 2)))
            }
            return rows
        }
        let sql = "SELECT id,part_of_speech,COALESCE(definition_en,''),COALESCE(example_en,''),COALESCE(meaning_fa,''),COALESCE(example_fa,'') FROM senses WHERE word_id=? ORDER BY part_of_speech,sense_order"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, word.id, -1, SQLITE_TRANSIENT)
        var rows: [Sense] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(Sense(id: str(statement, 0), partOfSpeech: str(statement, 1),
                              definition: str(statement, 2), example: str(statement, 3),
                              meaning: str(statement, 4), persianExample: str(statement, 5), bridge: ""))
        }
        return rows
    }

    func words(ids: Set<String>, direction: Direction) -> [Word] {
        guard !ids.isEmpty, let db = connect() else { return [] }
        defer { sqlite3_close(db) }
        let relevant = ids.filter { direction == .enFa ? !$0.hasPrefix("pair:") : $0.hasPrefix("pair:") }
        guard !relevant.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: relevant.count).joined(separator: ",")
        let sql = direction == .enFa ? """
            SELECT w.id,w.english,COALESCE(w.level,''),COALESCE(w.ipa,''),
              COALESCE((SELECT meaning_fa FROM senses WHERE word_id=w.id ORDER BY sense_order LIMIT 1),'')
            FROM words w WHERE w.id IN (\(marks)) ORDER BY w.english
            """ : "SELECT id,headword,preview FROM extra_entries WHERE direction=? AND id IN (\(marks)) ORDER BY headword"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        if direction != .enFa { sqlite3_bind_text(statement, 1, direction.rawValue, -1, SQLITE_TRANSIENT) }
        for (index, id) in relevant.enumerated() {
            let slot = Int32(index + 1 + (direction == .enFa ? 0 : 1))
            if direction == .enFa { sqlite3_bind_text(statement, slot, id, -1, SQLITE_TRANSIENT) }
            else { sqlite3_bind_int64(statement, slot, Int64(id.dropFirst(5)) ?? 0) }
        }
        var rows: [Word] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(direction == .enFa ? englishWord(statement) : pairWord(statement, direction))
        }
        return rows
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
