import XCTest

final class PracticeNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testPendingLessonUsesLearningTempoWithoutPresentingSpeedChallenges() {
        launch("learning-tempo")
        XCTAssertTrue(app.staticTexts["preparation.title"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["preparation.bpm"].label, "72 BPM")
        XCTAssertFalse(app.buttons["Seleccionar nivel Aprender, 70 BPM"].exists)
        tap(app.buttons["preparation.start"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "72 BPM")
    }

    func testSlowSuccessfulAttemptReturnsGraduallyToTheSameLesson() {
        launch("learning-recovery")
        XCTAssertTrue(app.buttons["Continuar"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["¡Buen ritmo!"].exists)
        XCTAssertFalse(app.buttons["Subir nivel"].exists)
        XCTAssertFalse(app.staticTexts["course.arrival.title"].exists)
        tap(app.buttons["Continuar"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.title"].label, "Fundamentos 1 · Bombo de respuesta")
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "70 BPM")
    }

    func testTouchPracticeUsesTwoLargePadsAndKeepsThemPlayableAfterRotation() {
        launch("touch-practice")
        let pads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.pad."))
        let kick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.pad.kick.")).firstMatch
        XCTAssertTrue(kick.waitForExistence(timeout: 30))
        XCTAssertEqual(pads.count, 2)
        XCTAssertGreaterThan(kick.frame.width, 100)
        kick.tap()
        XCTAssertTrue(app.staticTexts["practice.touch.lastHit"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["practice.touch.lastHit"].label, "Bombo")
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "Pads compactos · vertical"
        portrait.lifetime = .keepAlways
        add(portrait)

        XCUIDevice.shared.orientation = .landscapeLeft
        let snare = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.pad.snare.")).firstMatch
        XCTAssertTrue(snare.waitForExistence(timeout: 10))
        XCTAssertEqual(pads.count, 2)
        XCTAssertGreaterThan(snare.frame.width, 100)
        snare.tap()
        XCTAssertEqual(app.staticTexts["practice.touch.lastHit"].label, "Caja")
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Pads compactos · horizontal"
        landscape.lifetime = .keepAlways
        add(landscape)
    }

    func testTouchPracticeShowsOnlyTheEightSoundsOfTheFullHipHopPhrase() {
        launch("touch-many-sounds")
        let pads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.pad."))
        XCTAssertTrue(pads.firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(pads.count, 8)
        let sounds = Set(pads.allElementsBoundByIndex.map { $0.identifier.components(separatedBy: ".")[2] })
        XCTAssertEqual(sounds, ["kick", "snare", "rim", "clap", "hihat_closed", "hihat_open", "tom_high", "tom_low"])
        for pad in pads.allElementsBoundByIndex {
            let soundName = pad.label
            XCTAssertTrue(pad.isHittable)
            pad.tap()
            XCTAssertEqual(app.staticTexts["practice.touch.lastHit"].label, soundName)
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Pads compactos · ocho sonidos"
        image.lifetime = .keepAlways
        add(image)
    }

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
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "68 BPM")
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
