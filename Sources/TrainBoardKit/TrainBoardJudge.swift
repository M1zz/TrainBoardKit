import Foundation

// MARK: - Train board judge
//
// Decides, from the text on ONE row of a departure board or train front
// display, whether the rider should board that train. Two questions:
//   1. Is it going my way?            — destination/terminus on the row
//   2. Does it stop where I need it?  — train type on the row (급행, 急行, 快速)
//
// Knows nothing about any country's lines: the app hands in station names and
// train types. Shared by KORA (Korea) and 일본길찾기 (Japan), where train types
// and through services make question 2 the one riders get wrong most.

/// A train type that skips stations (급행 / 急行 / 快速). Trains with no
/// recognized type word are assumed to stop everywhere.
public struct TrainService: Hashable, Sendable {
    /// Stable key, e.g. "express".
    public let id: String
    /// Words that identify this type on a board or train front. Matched after
    /// normalization, so spacing doesn't matter.
    public let signWords: [String]
    /// Stations this type stops at.
    public let stops: Set<String>

    public init(id: String, signWords: [String], stops: Set<String>) {
        self.id = id
        self.signWords = signWords
        self.stops = stops
    }

    public func stops(at station: String) -> Bool { stops.contains(station) }
}

public struct TrainBoardJudge: Sendable {

    public enum Verdict: Equatable, Sendable {
        /// Right direction, stops at the rider's stations. `matched` is the
        /// station name that was read.
        case board(matched: String)
        /// Wrong direction. `matched` is the station name that was read.
        case wrongDirection(matched: String)
        /// Right direction, but this train type passes `station` without stopping.
        case skipsStop(serviceWord: String, station: String)
        /// The row names both neighbours ("← 잠원 | 고속터미널 | 교대 →") — can't tell.
        case ambiguous
    }

    /// Station names in the rider's direction (destination and beyond).
    public let forward: Set<String>
    /// Station names that mean the opposite direction / short of the destination.
    public let backward: Set<String>
    /// The next stop, when a station sign is pointing at it.
    public let nextStop: Set<String>
    /// Station the rider boards at and gets off at.
    public let boarding: String
    public let destination: String
    /// Station-skipping train types on this route.
    public let services: [TrainService]

    public init(forward: Set<String>, backward: Set<String>, nextStop: Set<String> = [],
                boarding: String = "", destination: String = "", services: [TrainService] = []) {
        self.forward = Set(forward.map(Self.normalizeStation))
        self.backward = Set(backward.map(Self.normalizeStation))
        self.nextStop = Set(nextStop.map(Self.normalizeStation))
        self.boarding = boarding
        self.destination = destination
        self.services = services
    }

    /// Judges a whole frame: rows top to bottom, the first row that says
    /// anything wins — on a departure board the top row is the next train.
    public func judge(rows: [String]) -> Verdict? {
        for row in rows {
            if let v = judge(row: row) { return v }
        }
        return nil
    }

    public func judge(row: String) -> Verdict? {
        let norm = Self.normalize(row)
        // The actual station name (from our marker sets) that was read — this is
        // what drove the verdict, shown to the rider so green/red isn't a mystery.
        let fwdHit = forward.first { !$0.isEmpty && norm.contains($0) }
        let bwdHit = backward.first { !$0.isEmpty && norm.contains($0) }
        let nextHit = nextStop.first { !$0.isEmpty && norm.contains($0) }

        // A valid destination wins: if any forward terminus/station is on the
        // row, it's going the right way (even if other text is present).
        if let f = fwdHit {
            if let skip = skippedStop(in: norm) { return skip }
            return .board(matched: f)
        }
        if let n = nextHit {
            // A station sign pointing to the next stop → this platform. But a
            // sign naming both neighbours can't tell us which side we're on.
            return bwdHit == nil ? .board(matched: n) : .ambiguous
        }
        if let b = bwdHit { return .wrongDirection(matched: b) }
        return nil
    }

    /// The train type on the row — the longest sign word wins, so "快速急行"
    /// isn't mistaken for "急行" — and the first of boarding/destination it skips.
    private func skippedStop(in norm: String) -> Verdict? {
        let hits = services.flatMap { service in
            service.signWords
                .filter { norm.contains(Self.normalize($0)) }
                .map { (service, $0) }
        }
        guard let (service, word) = hits.max(by: { Self.normalize($0.1).count < Self.normalize($1.1).count }) else {
            return nil
        }
        for station in [boarding, destination] where !station.isEmpty && !service.stops(at: station) {
            return .skipsStop(serviceWord: word, station: station)
        }
        return nil
    }

    /// OCR text: drop spaces/separators only. "오금행", "양재 방면", "横浜行"
    /// still contain the bare station name, so suffixes needn't be stripped.
    public static func normalize(_ s: String) -> String {
        var t = s
        for sep in [" ", "　", "·", "・", ",", "/"] {
            t = t.replacingOccurrences(of: sep, with: "")
        }
        return t
    }

    /// Station marker: like `normalize`, plus a trailing "역" / "駅"
    /// (서울역 → 서울, 横浜駅 → 横浜). Never strip 역/방/행 mid-name — 역삼 → "삼",
    /// 방이 → "이", 행당 → "당" would match nearly any sign.
    public static func normalizeStation(_ s: String) -> String {
        let t = normalize(s)
        if t.hasSuffix("역"), t.count > 2 { return String(t.dropLast()) }
        if t.hasSuffix("駅"), t.count > 1 { return String(t.dropLast()) }
        return t
    }
}

// MARK: - Rows from OCR boxes

extension TrainBoardJudge {
    /// A recognized text piece and its extent (Vision's normalized
    /// coordinates: 0 = bottom, 1 = top).
    public struct TextBox: Sendable {
        public let text: String
        public let minY: Double
        public let maxY: Double
        public let minX: Double
        public var midY: Double { (minY + maxY) / 2 }

        public init(text: String, minY: Double, maxY: Double, minX: Double) {
            self.text = text
            self.minY = minY
            self.maxY = maxY
            self.minX = minX
        }
    }

    /// Groups text pieces into board rows, top row first. Pieces whose vertical
    /// centre falls inside a row's band join it (a board row is often read as
    /// separate pieces: "급행" · "중앙보훈병원" · "전역출발"), left to right.
    public static func rows(from boxes: [TextBox]) -> [String] {
        var rows: [[TextBox]] = []
        for box in boxes.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.last?.first,
               box.midY >= last.minY, box.midY <= last.maxY {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }
}
