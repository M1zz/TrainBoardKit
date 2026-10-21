import XCTest
@testable import TrainBoardKit

/// 나라와 관계없는 판정 규칙. 노선 데이터는 시험 안에서 만든다.
final class TrainBoardJudgeTests: XCTestCase {

    // MARK: 한국 (9호선 일부)

    /// 서쪽(개화 방향)으로 가는 길: 탄 역보다 앞이 forward.
    private let line = ["개화", "김포공항", "노량진", "노들", "흑석", "동작", "고속터미널", "사평", "신논현", "언주"]
    private let express = TrainService(id: "express", signWords: ["급행"],
                                       stops: ["김포공항", "노량진", "동작", "고속터미널", "신논현"])

    private func westbound(from boarding: String, to destination: String) -> TrainBoardJudge {
        let di = line.firstIndex(of: destination)!
        let forward = Set(line[...di])
        let backward = Set(line).subtracting(forward).subtracting([boarding])
        return TrainBoardJudge(forward: forward, backward: backward,
                               boarding: boarding, destination: destination, services: [express])
    }

    func testLocalTrainBoardsAnywhere() {
        XCTAssertEqual(westbound(from: "신논현", to: "흑석").judge(row: "일반 개화행"), .board(matched: "개화"))
    }

    func testExpressBetweenExpressStopsBoards() {
        XCTAssertEqual(westbound(from: "신논현", to: "노량진").judge(row: "급행 김포공항"), .board(matched: "김포공항"))
    }

    func testExpressSkippingDestinationIsCaught() {
        XCTAssertEqual(westbound(from: "신논현", to: "흑석").judge(row: "급행 김포공항행"),
                       .skipsStop(serviceWord: "급행", station: "흑석"))
    }

    func testExpressSkippingBoardingIsCaught() {
        XCTAssertEqual(westbound(from: "언주", to: "노량진").judge(row: "급행 김포공항"),
                       .skipsStop(serviceWord: "급행", station: "언주"))
    }

    func testWrongDirectionStaysWrongEvenForExpress() {
        XCTAssertEqual(westbound(from: "사평", to: "흑석").judge(row: "급행 언주"), .wrongDirection(matched: "언주"))
    }

    func testStationSignNamingBothNeighboursIsAmbiguous() {
        let j = TrainBoardJudge(forward: ["개화"], backward: ["언주"], nextStop: ["사평"])
        XCTAssertEqual(j.judge(row: "← 사평 | 신논현 | 언주 →"), .ambiguous)
    }

    func testTopRowOfTheBoardDecides() {
        let boxes: [TrainBoardJudge.TextBox] = [
            .init(text: "일반", minY: 0.40, maxY: 0.50, minX: 0.1),
            .init(text: "김포공항", minY: 0.41, maxY: 0.49, minX: 0.3),
            .init(text: "김포공항", minY: 0.61, maxY: 0.69, minX: 0.3),
            .init(text: "급행", minY: 0.60, maxY: 0.70, minX: 0.1),
        ]
        let rows = TrainBoardJudge.rows(from: boxes)
        XCTAssertEqual(rows, ["급행 김포공항", "일반 김포공항"])
        let j = westbound(from: "신논현", to: "흑석")
        XCTAssertEqual(j.judge(rows: rows), .skipsStop(serviceWord: "급행", station: "흑석"))
        XCTAssertEqual(j.judge(rows: Array(rows.dropFirst())), .board(matched: "김포공항"))
    }

    // MARK: 일본식 표기 (가상의 노선 — 규칙만 본다)

    func testLongestTrainTypeWordWins() {
        // "快速急行" 안에 "急行" 이 들어 있다. 서는 역이 다르므로 긴 쪽으로 판정해야 한다.
        let kyuko = TrainService(id: "express", signWords: ["急行"], stops: ["A駅", "B", "D"])
        let kaisokuKyuko = TrainService(id: "rapidExpress", signWords: ["快速急行"], stops: ["A駅", "D"])
        let j = TrainBoardJudge(forward: ["D"], backward: ["Z"],
                                boarding: "A駅", destination: "B", services: [kyuko, kaisokuKyuko])
        XCTAssertEqual(j.judge(row: "快速急行 D行"), .skipsStop(serviceWord: "快速急行", station: "B"))
        XCTAssertEqual(j.judge(row: "急行 D行"), .board(matched: "D"))
    }

    func testJapaneseStationSuffixAndFullWidthSpace() {
        XCTAssertEqual(TrainBoardJudge.normalizeStation("横浜駅"), "横浜")
        let j = TrainBoardJudge(forward: ["横浜駅"], backward: [])
        XCTAssertEqual(j.judge(row: "各停　横浜 行"), .board(matched: "横浜"))
    }

    func testShorterNameInsideLongerNameIsNotRead() {
        // 目黒 방향이 맞고 中目黒 는 반대쪽일 때, "中目黒行" 은 반대쪽이다.
        let j = TrainBoardJudge(forward: ["目黒", "白金台"], backward: ["中目黒", "赤羽岩淵"])
        XCTAssertEqual(j.judge(row: "各停 中目黒行"), .wrongDirection(matched: "中目黒"))
        XCTAssertEqual(j.judge(row: "各停 目黒行"), .board(matched: "目黒"))
    }

    func testSmallAndFullSizeKeAreTheSame() {
        let j = TrainBoardJudge(forward: ["市ヶ谷"], backward: [])
        XCTAssertEqual(j.judge(row: "市ケ谷行"), .board(matched: "市ケ谷"))
    }
}
