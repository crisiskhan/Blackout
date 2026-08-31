import BlackoutCore
import XCTest

final class GuideOfflineTests: XCTestCase {
    func testBiomeFromThisPhoneGPS() {
        XCTAssertEqual(GuideBiome.infer(latitude: 28.5, longitude: -81.4), .florida)
        XCTAssertEqual(GuideBiome.infer(latitude: 31.7619, longitude: -106.485), .texas)
        XCTAssertEqual(GuideBiome.infer(latitude: 35.1, longitude: -106.6), .newMexico)
        XCTAssertEqual(GuideBiome.infer(latitude: 42.7, longitude: -73.8), .newYork)
        XCTAssertEqual(GuideBiome.infer(latitude: 39.74, longitude: -104.99), .southernRockies)
        XCTAssertEqual(GuideBiome.infer(latitude: nil, longitude: nil), .unknown)
        XCTAssertEqual(GuideBiome.infer(latitude: 51.5, longitude: -0.1), .unknown)
    }

    func testAskRankerIsHonestWhenGPSAndBiomeUnknown() {
        let noGPS = GuideQueryContext(
            hour: 14,
            elevationMeters: nil,
            batteryLevel: 0.8,
            sosArmed: false,
            month: 8,
            latitude: nil,
            longitude: nil
        )
        XCTAssertFalse(noGPS.gpsKnown)
        XCTAssertEqual(noGPS.biome, .unknown)
        XCTAssertEqual(GuideAskRanker.honestyLine(noGPS), "No GPS. Biome unknown. Month still applied.")

        let unknownBiome = GuideQueryContext(
            hour: 14,
            elevationMeters: nil,
            batteryLevel: 0.8,
            sosArmed: false,
            month: 1,
            latitude: 51.5,
            longitude: -0.12
        )
        XCTAssertTrue(unknownBiome.gpsKnown)
        XCTAssertEqual(unknownBiome.biome, .unknown)
        XCTAssertEqual(
            GuideAskRanker.honestyLine(unknownBiome),
            "GPS on. Biome unknown. Month still applied."
        )
    }

    func testAskRankerUsesGPSBiomeAndMonthOnDevice() {
        let augustFlorida = GuideQueryContext(
            hour: 13,
            elevationMeters: 4,
            batteryLevel: 0.7,
            sosArmed: false,
            month: 8,
            latitude: 27.8,
            longitude: -82.6
        )
        XCTAssertEqual(augustFlorida.biome, .florida)
        XCTAssertEqual(
            GuideAskRanker.honestyLine(augustFlorida),
            "GPS, biome, and month on this phone."
        )

        var heat: [String: Double] = [:]
        var frost: [String: Double] = [:]
        let articles: [(String, String, [String])] = [
            ("situation-heat", "first-aid", ["heat", "hot"]),
            ("vision-fl-saw-palmetto", "food-plants", ["fl", "plant"]),
            ("vision-ny-unknown", "food-plants", ["ny", "plant"]),
            ("aid-frost", "first-aid", ["frost", "cold"]),
            ("shelter-site", "shelter", ["shelter"]),
        ]
        GuideAskRanker.apply(augustFlorida, to: &heat, articles: articles)
        XCTAssertGreaterThan(heat["situation-heat"] ?? 0, heat["aid-frost"] ?? 0)
        XCTAssertGreaterThan(heat["vision-fl-saw-palmetto"] ?? 0, heat["vision-ny-unknown"] ?? 0)

        let januaryRockies = GuideQueryContext(
            hour: 21,
            elevationMeters: 3100,
            batteryLevel: 0.4,
            sosArmed: false,
            month: 1,
            latitude: 39.74,
            longitude: -105.25
        )
        GuideAskRanker.apply(januaryRockies, to: &frost, articles: articles)
        XCTAssertGreaterThan(frost["aid-frost"] ?? 0, frost["situation-heat"] ?? 0)
        XCTAssertGreaterThan(frost["shelter-site"] ?? 0, 0)
    }

    func testMedicalLostTreeStartsWithTriageNotSearch() {
        XCTAssertTrue(GuideTriage.isMedicalOrLost(id: "aid-bleeding", topic: "first-aid", tags: ["bleed"]))
        XCTAssertTrue(GuideTriage.isMedicalOrLost(id: "situation-lost", topic: "navigation", tags: ["lost"]))
        XCTAssertTrue(GuideTriage.isMedicalOrLost(id: "party-split", topic: "situation", tags: ["split"]))
        XCTAssertTrue(GuideTriage.isMedicalOrLost(id: "kid-heat", topic: "first-aid", tags: ["kid", "heat"]))
        XCTAssertFalse(GuideTriage.isMedicalOrLost(id: "water-boil", topic: "water", tags: ["boil"]))
        XCTAssertEqual(GuideTriage.entry, .adultKidPartySplit)
        XCTAssertNotEqual(GuideTriage.entry, .searchBox)

        XCTAssertEqual(GuideTriage.route(.partySplit, treeID: "situation-lost", tags: ["lost"]), .partySplit)
        XCTAssertEqual(GuideTriage.route(.adult, treeID: "aid-bleeding", tags: ["bleed"]), .adultTree)
        XCTAssertEqual(
            GuideTriage.route(.kid, treeID: "situation-heat", tags: ["heat"]),
            .kidModes([.kidHeat])
        )
        XCTAssertEqual(
            GuideTriage.route(.kid, treeID: "aid-snake", tags: ["bite", "snake"]),
            .kidModes([.kidBite])
        )
        XCTAssertEqual(
            GuideTriage.route(.kid, treeID: "situation-lost", tags: ["lost"]),
            .kidModes([.kidLost])
        )
        let allKids = GuideTriage.route(.kid, treeID: "aid-bleeding", tags: ["bleed"])
        XCTAssertEqual(allKids, .kidModes([.kidLost, .kidHeat, .kidBite]))
    }

    func testSpeakNextStepOnlyNeverTheEssay() {
        let steps = [
            "Shade now. Pack off.",
            "Sip small if they can keep it down.",
            "Watch quiet, cranky, or wobbly.",
        ]
        XCTAssertEqual(GuideSpeak.nextStepOnly(steps: steps, index: 0), steps[0])
        XCTAssertEqual(GuideSpeak.nextStepOnly(steps: steps, index: 1), steps[1])
        XCTAssertNil(GuideSpeak.nextStepOnly(steps: steps, index: 9))
        let spoken = GuideSpeak.nextStepOnly(steps: steps, index: 0) ?? ""
        XCTAssertFalse(spoken.contains(steps[1]))
        XCTAssertFalse(spoken.contains(steps[2]))
        XCTAssertEqual(GuideSpeak.controlNext, "Next")
        XCTAssertEqual(GuideSpeak.controlStop, "Stop")
        XCTAssertGreaterThanOrEqual(GuideSpeak.controlHeight, 72)
    }

    func testOutingMemorySkipsWeightAndAllergyThenClearsOnOutingEnd() {
        let defaults = UserDefaults(suiteName: "guide.outing.memory.test")!
        defaults.removePersistentDomain(forName: "guide.outing.memory.test")
        var memory = OutingMemory(outingID: "exp-1")
        XCTAssertTrue(memory.shouldAskWeight)
        XCTAssertTrue(memory.shouldAskAllergy)
        memory.rememberWeight(72)
        memory.rememberAllergy("none")
        XCTAssertFalse(memory.shouldAskWeight)
        XCTAssertFalse(memory.shouldAskAllergy)
        OutingMemoryStore.save(memory, defaults: defaults)
        let loaded = OutingMemoryStore.load(defaults: defaults)
        XCTAssertEqual(loaded.weightKg, 72)
        XCTAssertEqual(loaded.allergyNote, "none")
        OutingMemoryStore.clearIfOutingEnded(openExpeditionID: nil, defaults: defaults)
        let cleared = OutingMemoryStore.load(defaults: defaults)
        XCTAssertTrue(cleared.shouldAskWeight)
        XCTAssertTrue(cleared.shouldAskAllergy)
        XCTAssertFalse(OutingMemory.shipsOffDevice)
    }

    func testCarePinIsFirstLineFromHeadingsOrExistingCopy() {
        let headed = """
        ### Stop if
        They stop sweating and cannot make sense.

        ### Get to care
        Confused, fainting, or cannot keep water down.

        ### Do
        1. Shade now.
        """
        let fromHeadings = GuideCarePinParser.parse(headed)
        XCTAssertEqual(fromHeadings.stopIf, "They stop sweating and cannot make sense.")
        XCTAssertEqual(fromHeadings.getToCare, "Confused, fainting, or cannot keep water down.")
        XCTAssertTrue(fromHeadings.firstLine?.contains("Stop if") == true)
        XCTAssertTrue(fromHeadings.firstLine?.hasPrefix("Stop if") == true)

        let body = """
        ### Situation
        Blood is leaving the person.

        ### Do
        1. Pressure.
        7. Get to care. Write what you did and when.

        ### Cautions
        - A trickle after a punchy fall can still be a lot of blood inside a boot.
        - Improvised wraps that only circle the limb are decorations.
        """
        let extracted = GuideCarePinParser.parse(body)
        XCTAssertEqual(
            extracted.stopIf,
            "A trickle after a punchy fall can still be a lot of blood inside a boot."
        )
        XCTAssertEqual(extracted.getToCare, "Get to care. Write what you did and when.")
        XCTAssertNotNil(extracted.firstLine)
    }

    func testGearAwareShowsImproviseWhenTourniquetMissing() {
        let steps = [
            "Direct pressure with cloth.",
            "If a limb is pumping and pressure fails, a tourniquet high and tight on that limb.",
            "Improvised wraps that only circle the limb without pressure on the hole are decorations.",
            "Lie them down. Keep them warm.",
        ]
        let empty = OutingGearRoster(checked: [])
        XCTAssertTrue(empty.isEmpty)
        let emptyResult = GuideGearAware.select(steps: steps, gear: empty)
        XCTAssertEqual(emptyResult.branch, .honestEmpty)
        XCTAssertFalse(emptyResult.steps.contains(where: { $0.lowercased().contains("tourniquet high") }))
        XCTAssertTrue(emptyResult.steps.contains(where: { $0.lowercased().contains("improvise") }))

        let noTq = OutingGearRoster(checked: ["headlamp", "knife"])
        let improvise = GuideGearAware.select(steps: steps, gear: noTq)
        XCTAssertEqual(improvise.branch, .improvise)
        XCTAssertFalse(improvise.steps.contains(where: { $0.lowercased().contains("tourniquet high") }))

        let withTq = OutingGearRoster(checked: ["tourniquet", "gauze"])
        let kit = GuideGearAware.select(steps: steps, gear: withTq)
        XCTAssertEqual(kit.branch, .kit)
        XCTAssertTrue(kit.steps.contains(where: { $0.lowercased().contains("tourniquet") }))
    }

    func testVisionStaysTwoPercentsLookalikeAndUnknownNoEat() {
        let body = """
        ID confidence (typical visual): 74%. Runner-up/lookalike: 18% (cabbage palm).

        ### Documented parts
        Ripe fruit documented as food in some traditions after harvest.
        """
        let reading = GuideVisionID.parse(title: "Saw palmetto", body: body)
        XCTAssertEqual(reading?.idPercent, 74)
        XCTAssertEqual(reading?.lookalikePercent, 18)
        XCTAssertEqual(reading?.lookalikeName, "cabbage palm")
        XCTAssertEqual(reading?.label, "Saw palmetto")
        XCTAssertFalse(reading?.isUnknown == true)
        XCTAssertNil(reading?.eatVerdict)
        XCTAssertTrue(GuideVisionID.neverEatVerdict)

        let unknown = GuideVisionID.unknownReading(biome: .unknown)
        XCTAssertTrue(unknown.isUnknown)
        XCTAssertNil(unknown.eatVerdict)
        XCTAssertEqual(unknown.idPercent, 8)
        XCTAssertEqual(GuideVisionID.deckPrefix(for: .florida), "fl")
        XCTAssertEqual(GuideVisionID.deckPrefix(for: .texas), "tx")
        XCTAssertEqual(GuideVisionID.deckPrefix(for: .newYork), "ny")
        XCTAssertEqual(GuideVisionID.deckPrefix(for: .newMexico), "nm")
        XCTAssertNil(GuideVisionID.deckPrefix(for: .unknown))
    }

    func testPictogramStepsUseSOSChromeAndKeepText() {
        let steps = GuideTreeText.doSteps(
            in: """
            ### Do
            1. Stop the group. Mark this spot.
            2. Three whistle blasts. Wait.
            3. Get to care.
            """
        )
        XCTAssertEqual(steps.count, 3)
        let pictos = GuidePictogramSteps.symbols(for: steps)
        XCTAssertEqual(pictos.count, 3)
        XCTAssertTrue(GuidePictogramSteps.usesSOSChrome)
        XCTAssertTrue(GuidePictogramSteps.textStillAvailable)
        XCTAssertEqual(pictos[0].systemName, "hand.raised.fill")
        XCTAssertEqual(pictos[1].systemName, "speaker.wave.3.fill")
    }

    func testGuideCardOpensExistingMapJobs() {
        XCTAssertEqual(
            GuideMapJob.jobs(forArticleID: "water-find-rockies", tags: ["find water", "creek"], topic: "water"),
            [.findWater]
        )
        XCTAssertTrue(
            GuideMapJob.jobs(forArticleID: "situation-lost", tags: ["lost"], topic: "navigation")
                .contains(.findCivilization)
        )
        XCTAssertTrue(
            GuideMapJob.jobs(forArticleID: "situation-lost", tags: ["lost"], topic: "navigation")
                .contains(.lastMark)
        )
        XCTAssertEqual(GuideMapJob.findWater.title, "Find water")
        XCTAssertEqual(GuideMapJob.findCivilization.title, "Find civilization")
        XCTAssertEqual(GuideMapJob.lastMark.title, "Last MARK")
    }

    func testSkillsDoAlongIsTimedHardStopNotAGame() {
        XCTAssertEqual(GuideDoAlong.classify(id: "skill-ferro-fire", tags: ["fire"], topic: "fire"), .fire)
        XCTAssertEqual(GuideDoAlong.classify(id: "skill-debris-hut", tags: ["shelter"], topic: "shelter"), .shelter)
        XCTAssertEqual(GuideDoAlong.classify(id: "skill-boil-water", tags: ["water"], topic: "water"), .water)
        XCTAssertNil(GuideDoAlong.classify(id: "skill-knot-bowline", tags: ["knot"], topic: "bushcraft"))
        XCTAssertFalse(GuideDoAlong.isGame)
        XCTAssertFalse(GuideDoAlong.awardsXP)
        XCTAssertEqual(GuideDoAlong.hardStopCopy, "That's enough, walk.")
        XCTAssertFalse(GuideDoAlong.shouldHardStop(elapsed: 60, kind: .fire))
        XCTAssertTrue(GuideDoAlong.shouldHardStop(elapsed: GuideDoAlong.hardStopSeconds(for: .fire), kind: .fire))
    }

    func testChromeAndTabsStayLocked() {
        XCTAssertEqual(RootChromeLock.tabCount, 4)
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertFalse(FieldJobMode.replacesSOS)
    }

    func testFieldAskHomeIsAskPlusChipsNotEncyclopedia() {
        XCTAssertTrue(FieldAskHomeLock.homeIsAskPlusChips)
        XCTAssertFalse(FieldAskHomeLock.paintsEncyclopediaOnHome)
        XCTAssertFalse(FieldAskHomeLock.paintsMedicalLostWallOnHome)
        XCTAssertFalse(FieldAskHomeLock.paintsPackCountEssayOnHome)
        XCTAssertFalse(FieldAskHomeLock.stacksAnswerCards)
        XCTAssertTrue(FieldAskHomeLock.oneCardAtATime)
        XCTAssertTrue(FieldAskHomeLock.stopReturnsToAsk)
        XCTAssertEqual(FieldAskHomeLock.askPlaceholder, "What do you need?")
        XCTAssertEqual(FieldAskHomeLock.browseLabel, "Browse")
        XCTAssertEqual(FieldAskHomeLock.unknownCopy, "Unknown is valid. Try a chip or ask again.")
        XCTAssertEqual(
            FieldAskHomeLock.homeChipTitles,
            ["Fire", "Water", "Shelter", "First aid", "Injury", "Lost", "Signaling"]
        )
        XCTAssertEqual(FieldAskHomeLock.homeChipArticleID("Fire"), "fire-when")
        XCTAssertEqual(FieldAskHomeLock.homeChipArticleID("Water"), "situation-water")
        XCTAssertEqual(FieldAskHomeLock.homeChipArticleID("Shelter"), "shelter-emergency")
        XCTAssertEqual(FieldAskHomeLock.homeChipArticleID("First aid"), "aid-scene")
        XCTAssertEqual(FieldAskHomeLock.homeChipArticleID("Injury"), "situation-injury")
        XCTAssertEqual(FieldAskHomeLock.homeChipArticleID("Lost"), "situation-lost")
        XCTAssertEqual(FieldAskHomeLock.homeChipArticleID("Signaling"), "signal-whistle")
        XCTAssertNil(FieldAskHomeLock.homeChipArticleID("Split"))
        XCTAssertTrue(FieldAskHomeLock.showsHome(hasActiveArticle: false, browsing: false))
        XCTAssertFalse(FieldAskHomeLock.showsHome(hasActiveArticle: true, browsing: false))
        XCTAssertFalse(FieldAskHomeLock.showsHome(hasActiveArticle: false, browsing: true))
        XCTAssertTrue(FieldAskHomeLock.presentsStepPager(hitCount: 1))
        XCTAssertFalse(FieldAskHomeLock.presentsStepPager(hitCount: 2))
        XCTAssertTrue(FieldAskHomeLock.presentsBrowse(hitCount: 3))
        XCTAssertFalse(FieldAskHomeLock.presentsBrowse(hitCount: 1))
        XCTAssertTrue(FieldAskHomeLock.presentsUnknown(hitCount: 0))
        XCTAssertFalse(FieldAskHomeLock.presentsUnknown(hitCount: 1))
        XCTAssertTrue(FieldAskHomeLock.skillsIsCurriculumList)
        XCTAssertFalse(FieldAskHomeLock.skillsDumpsAllPlates)
        XCTAssertEqual(RootChromeLock.tabCount, 4)
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertTrue(MapChromeLock.fieldPlateUsesSafeArea)
        XCTAssertEqual(MapChromeLock.fieldContentHorizontalInset, 20)
        XCTAssertTrue(MapChromeLock.duskCrushesCountyLabels)
        XCTAssertFalse(MapChromeLock.paintsVitalsChrome)
    }
}
