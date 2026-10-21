import XCTest

final class PracticeNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app.terminate() }

    private func launch(_ scenario: String = "result") {
        app.launchEnvironment["XROLL_UI_TEST_SCENARIO"] = scenario
        app.launch()
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), file: file, line: line)
        for _ in 0..<8 {
            // Un botón parcialmente detrás del indicador inferior puede ser
            // isHittable sin que el centro reciba el toque sintetizado.
            if element.isHittable && element.frame.maxY < app.frame.maxY - 60 { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.tap()
    }

    func testNextExerciseStartsPracticeWithoutPreparation() {
        launch()
        tap(app.buttons["Continuar"])
        let title = app.staticTexts["practice.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "I-02 · Añade charles")
        XCTAssertFalse(app.buttons["preparation.start"].exists)
        XCTAssertTrue(app.buttons["Pausar práctica"].exists)
    }

    func testOneStarPassContinuesTheCampaignWithoutTempoChoices() {
        launch("one-star-result")
        XCTAssertTrue(app.buttons["Continuar"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Subir nivel"].exists)
        tap(app.buttons["Continuar"])
        let title = app.staticTexts["practice.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "I-02 · Añade charles")
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "70 BPM")
        XCTAssertFalse(app.buttons["preparation.start"].exists)
    }

    func testReturnToMenuSelectsCourse() {
        launch()
        tap(app.buttons["result.menu"])
        XCTAssertTrue(app.tabBars.buttons["Curso"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Curso"].isSelected)
    }

    func testReturnToMenuSelectsFillsForAFillExercise() {
        launch("fill-result")
        tap(app.buttons["result.menu"])
        XCTAssertTrue(app.tabBars.buttons["Redobles"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Redobles"].isSelected)
    }

    func testCheckpointShowsItsPreparationBeforeStarting() {
        launch("checkpoint-preparation")
        let title = app.staticTexts["preparation.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(title.label, "Reto de estación · Fundamentos")
        XCTAssertFalse(app.staticTexts["practice.title"].exists)
        tap(app.buttons["preparation.start"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.title"].label, "Reto de estación · Fundamentos")
    }

    func testChosenCourseExerciseKeepsItsOwnPreparationAndStartsThatRhythm() {
        launch("exercise-preparation")
        let title = app.staticTexts["preparation.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(title.label, "Reggae 02 · Aperturas a contratiempo")
        XCTAssertEqual(app.staticTexts["preparation.guidance.exercise"].label, title.label)
        XCTAssertFalse(app.staticTexts["TU SIGUIENTE PASO"].exists)
        XCTAssertFalse(app.buttons["Empezar siguiente paso"].exists)
        tap(app.buttons["preparation.start"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.title"].label, "Reggae 02 · Aperturas a contratiempo")
    }

    func testPassedFutureCheckpointExplainsAndOpensThePendingChapter() {
        launch("checkpoint-result")
        let outcome = app.staticTexts["checkpoint.outcome"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 30))
        XCTAssertTrue(outcome.label.contains("completa antes Iniciación"))
        XCTAssertTrue(outcome.label.contains("resultado queda guardado"))
        tap(app.buttons["checkpoint.openPending"])
        let title = app.staticTexts["preparation.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "I-01 · Bombo y caja")
        XCTAssertFalse(app.staticTexts["practice.title"].exists)
    }

    func testRailwayShowsOnlyTheCurrentStationLevelsAndOpensItsRecommendedLevel() {
        launch("campaign-map")
        let play = app.buttons["course.next"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        XCTAssertTrue(play.label.contains("Empezar nivel 1"))
        XCTAssertEqual(app.staticTexts["course.map.title"].label, "METRO DEL RITMO")
        XCTAssertFalse(app.staticTexts["CAMPAÑA DEL RITMO"].exists)
        XCTAssertTrue(app.buttons["course.level.00_i_01_bombo_caja"].exists)
        XCTAssertFalse(app.buttons["course.level.01_fund_01_pulso"].exists)
        let mapImage = XCTAttachment(screenshot: app.screenshot())
        mapImage.name = "Metro del Ritmo · iPhone"
        mapImage.lifetime = .keepAlways
        add(mapImage)
        tap(play)
        XCTAssertTrue(app.staticTexts["preparation.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["preparation.title"].label, "I-01 · Bombo y caja")
    }

    func testRailwayRecommendsTheStationChallengeAfterItsLevels() {
        launch("campaign-boss-ready")
        let play = app.buttons["course.next"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        XCTAssertTrue(play.label.contains("Preparar reto final"))
        tap(play)
        let title = app.staticTexts["preparation.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Reto de estación · Iniciación")
        tap(app.buttons["preparation.start"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.title"].label, "Reto de estación · Iniciación")
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "72 BPM")
    }

    func testStationCompletionHasOneContinuationToTheNextStop() {
        launch("campaign-victory")
        let title = app.staticTexts["course.arrival.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(title.label, "¡Estación 1 completada!")
        XCTAssertTrue(app.staticTexts["course.arrival.message"].label.contains("Fundamentos"))
        XCTAssertFalse(app.buttons["Subir nivel"].exists)
        XCTAssertTrue(app.buttons["course.arrival.continue"].label.contains("Siguiente parada"))
        tap(app.buttons["course.arrival.continue"])
        XCTAssertTrue(app.staticTexts["preparation.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["preparation.title"].label, "Fundamentos 1 · Bombo de respuesta")
        XCTAssertFalse(app.staticTexts["TU SIGUIENTE PASO"].exists)
    }
}
