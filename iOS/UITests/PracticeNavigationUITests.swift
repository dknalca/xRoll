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

    func testGuidedHomeHasOnePreparedTaskAndIgnoresPreviousAdvancedSessionSettings() {
        launch("guided-home")
        let start = app.buttons["guided.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertEqual(start.label, "Vamos a tocar")
        XCTAssertEqual(app.staticTexts["guided.exercise"].label, "I-01 · Bombo y caja")
        XCTAssertFalse(app.buttons["Entrenar pulso interno"].exists)
        XCTAssertFalse(app.buttons["Seleccionar nivel Base, 85 BPM"].exists)
        XCTAssertFalse(app.staticTexts["preparation.title"].exists)
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "Inicio guiado · una tarea y una acción"
        home.lifetime = .keepAlways
        add(home)
        tap(start)
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "68 BPM")
        XCTAssertEqual(app.staticTexts["practice.stage"].label, "Juntos · sin puntuar")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.pad.")).count, 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Inicio guiado · ritmo completo preparado"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testEquipmentWizardShowsOnlyThePendingStepAndCannotSkipCalibration() {
        launch("guided-setup")
        tap(app.buttons["guided.start"])
        let step = app.staticTexts["equipment.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        XCTAssertEqual(step.label, "1 · Escucha un sonido")
        XCTAssertFalse(app.staticTexts["LAYOUT FUNCIONAL"].exists)
        XCTAssertFalse(app.buttons["equipment.confirmSound"].exists)
        tap(app.buttons["equipment.probeSound"])
        tap(app.buttons["equipment.confirmSound"])
        XCTAssertEqual(step.label, "2 · Comprueba tus pads")
        tap(app.buttons["equipment.probePad"])
        XCTAssertEqual(step.label, "3 · Toca siguiendo el clic")
        XCTAssertTrue(app.buttons["equipment.calibrate"].exists)
        XCTAssertFalse(app.buttons["equipment.start"].exists)
        XCTAssertFalse(app.staticTexts["MAPAS PORTABLES"].exists)
    }

    func testEquipmentReusesAValidCalibrationAndOffersAnExplicitRecheck() {
        launch("guided-home")
        XCTAssertTrue(app.tabBars.buttons["Equipo"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Equipo"].tap()
        let step = app.staticTexts["equipment.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        XCTAssertEqual(step.label, "Todo listo")
        XCTAssertFalse(app.buttons["equipment.probeSound"].exists)
        tap(app.buttons["equipment.recheck"])
        XCTAssertEqual(step.label, "1 · Escucha un sonido")
        tap(app.buttons["equipment.probeSound"])
        tap(app.buttons["equipment.confirmSound"])
        tap(app.buttons["equipment.probePad"])
        XCTAssertEqual(step.label, "Todo listo")
        XCTAssertFalse(app.buttons["equipment.calibrate"].exists)
        tap(app.buttons["equipment.start"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
    }

    func testPersonalizationIsCollapsedAndPreservesAnExplicitTempoWhenOpened() {
        launch("guided-home")
        tap(app.descendants(matching: .any).matching(identifier: "guided.customize").firstMatch)
        tap(app.buttons["Abrir preparación personalizada"])
        XCTAssertTrue(app.staticTexts["preparation.title"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["NIVEL DE TEMPO"].exists)
        tap(app.descendants(matching: .any).matching(identifier: "preparation.customize").firstMatch)
        tap(app.descendants(matching: .any).matching(identifier: "preparation.tempos").firstMatch)
        tap(app.buttons["Seleccionar nivel Base, 85 BPM"])
        tap(app.buttons["preparation.start"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "85 BPM")
    }

    func testTechnicalAudioOptionsRemainAvailableButStartCollapsed() {
        launch("guided-home")
        tap(app.buttons["Opciones"])
        XCTAssertTrue(app.switches["Escuchar la claqueta"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["SALIDA DE AUDIO"].exists)
        tap(app.descendants(matching: .any).matching(identifier: "options.advanced").firstMatch)
        XCTAssertTrue(app.staticTexts["SALIDA DE AUDIO"].waitForExistence(timeout: 5))
    }

    func testGenreAwardsSelectOnlyOneChallengeAtTheSameMusicalTempo() {
        launch("exercise-preparation")
        XCTAssertTrue(app.staticTexts["preparation.title"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["preparation.bpm"].label, "75 BPM")
        tap(app.descendants(matching: .any).matching(identifier: "preparation.customize").firstMatch)
        tap(app.descendants(matching: .any).matching(identifier: "preparation.tempos").firstMatch)
        let base = app.buttons["preparation.tempo.0"]
        let precision = app.buttons["preparation.tempo.1"]
        XCTAssertTrue(base.isSelected)
        tap(precision)
        XCTAssertTrue(precision.isSelected)
        XCTAssertFalse(base.isSelected)
        XCTAssertEqual(precision.value as? String, "80 % · 2 compases")
        tap(app.buttons["preparation.start"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "75 BPM")
    }

    func testRehearsalChangesFromPlayingTogetherToScoredPracticeWithTheSameTouchPads() {
        launch("rehearsal-preparation")
        tap(app.buttons["preparation.start"])
        let stage = app.staticTexts["practice.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        XCTAssertEqual(stage.label, "Juntos · sin puntuar")
        let pads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.pad."))
        let ids = pads.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(ids.count, 2)
        pads.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["practice.touch.lastHit"].exists)
        let transition = expectation(for: NSPredicate(format: "label == %@", "Ahora tú · sigue el ritmo"), evaluatedWith: stage)
        wait(for: [transition], timeout: 15)
        XCTAssertEqual(pads.allElementsBoundByIndex.map(\.identifier), ids)
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "120 BPM")
    }

    func testStoppingDuringRehearsalDoesNotCreditBarsOrRestartFromADelayedCallback() {
        launch("rehearsal-preparation")
        tap(app.buttons["preparation.start"])
        XCTAssertTrue(app.staticTexts["practice.stage"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.stage"].label, "Juntos · sin puntuar")
        tap(app.buttons["Terminar práctica"])
        XCTAssertTrue(app.staticTexts["0 compases completados"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 7)
        XCTAssertFalse(app.staticTexts["practice.title"].exists)
        XCTAssertFalse(app.staticTexts["course.arrival.title"].exists)
    }

    func testCorrectiveCellIncludesAReferenceAndReturnsToTheOriginalGrooveAndTempo() {
        launch("rescue-result")
        tap(app.descendants(matching: .any).matching(identifier: "result.options").firstMatch)
        tap(app.buttons["Practicar la parte difícil"])
        XCTAssertTrue(app.staticTexts["practice.stage"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.stage"].label, "Juntos · sin puntuar")
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "128 BPM")
        let returnToGroove = app.buttons["result.primary"]
        XCTAssertTrue(returnToGroove.waitForExistence(timeout: 40))
        XCTAssertEqual(returnToGroove.label, "Volver al groove completo")
        tap(returnToGroove)
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "160 BPM")
        XCTAssertEqual(app.staticTexts["practice.stage"].label, "Juntos · sin puntuar")
    }

    func testProgressExportReportsTheNumberOfAttemptsAndOffersTheCompleteFile() {
        launch("progress-export")
        tap(app.buttons["Exportar JSON"])
        let exported = app.staticTexts["progress.export.status"]
        let ready = expectation(for: NSPredicate(format: "label CONTAINS %@", "Se exportó 1 intento"), evaluatedWith: exported)
        wait(for: [ready], timeout: 15)
        XCTAssertTrue(app.buttons["Compartir exportación"].exists)
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

    func testResultShowsOneSoundRecommendationAndContinuationBeforeTechnicalDetails() {
        launch("result-late")
        let diagnosis = app.staticTexts["result.diagnosis"]
        XCTAssertTrue(diagnosis.waitForExistence(timeout: 30))
        XCTAssertTrue(diagnosis.label.contains("Caja"))
        XCTAssertTrue(diagnosis.label.contains("tarde"))
        XCTAssertTrue(app.staticTexts["result.recommendation"].label.contains("antes"))
        let continuation = app.buttons["course.continue"]
        XCTAssertTrue(continuation.isHittable)
        XCTAssertFalse(app.staticTexts["EVIDENCIA TEMPORAL"].exists)
        XCTAssertFalse(app.buttons["Subir nivel"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Resultado · recomendación y continuación"
        image.lifetime = .keepAlways
        add(image)
        tap(continuation)
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
    }

    func testSparseResultAvoidsTimingClaimsAndKeepsDetailsCollapsedButAccessible() {
        launch("result-insufficient")
        let diagnosis = app.staticTexts["result.diagnosis"]
        XCTAssertTrue(diagnosis.waitForExistence(timeout: 30))
        XCTAssertTrue(diagnosis.label.contains("faltan golpes"))
        XCTAssertTrue(app.buttons["result.primary"].isHittable)
        XCTAssertFalse(app.staticTexts["EVIDENCIA TEMPORAL"].exists)
        tap(app.descendants(matching: .any).matching(identifier: "result.details").firstMatch)
        XCTAssertTrue(app.staticTexts["EVIDENCIA TEMPORAL"].waitForExistence(timeout: 5))
    }

    func testTempoChallengeStaysOptionalAndStartsOnlyAfterOpeningMoreOptions() {
        launch("fill-result")
        let primary = app.buttons["result.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        XCTAssertEqual(primary.label, "Repetir para consolidar")
        XCTAssertFalse(app.buttons["Subir nivel"].exists)
        tap(app.descendants(matching: .any).matching(identifier: "result.options").firstMatch)
        tap(app.buttons["Subir nivel"])
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["practice.bpm"].label, "85 BPM")
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
        XCTAssertTrue(element.waitForExistence(timeout: 30), app.debugDescription, file: file, line: line)
        for _ in 0..<8 {
            // Un botón parcialmente detrás del indicador inferior puede ser
            // isHittable sin que el centro reciba el toque sintetizado.
            if element.isHittable && element.frame.minY > app.frame.minY + 40 && element.frame.maxY < app.frame.maxY - 60 { break }
            if element.frame.minY < app.frame.minY + 40 { app.swipeDown() }
            else { app.swipeUp() }
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
        XCTAssertFalse(app.staticTexts["preparation.guidance.exercise"].exists, "El detalle técnico permanece plegado")
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
