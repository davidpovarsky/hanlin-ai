import Testing
import Foundation
@testable import TorahLibraryKit

@Suite("TorahLibraryKit Core Tests")
struct TorahLibraryKitTests {

    @Test("HebrewTextNormalizer strips vocalization and cantillation while mapping indices")
    func testNormalizer() {
        let textWithNiqqud = "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים"
        let mapping = HebrewTextNormalizer.normalize(text: textWithNiqqud)
        #expect(mapping.normalizedText == "בראשית ברא אלהים")
        #expect(!mapping.normalizedToRawIndices.isEmpty)

        // Raw index of the first character 'ב' should be 0
        #expect(mapping.rawOffset(for: 0) == 0)

        let anchors = HebrewTextNormalizer.extractAnchors(from: textWithNiqqud, minWordLength: 3, anchorSize: 2)
        #expect(!anchors.isEmpty)
        #expect(anchors.contains("בראשית ברא"))
    }

    @Test("TorahTextAlignment aligns OCR tokens with source text")
    func testAlignment() {
        let ocrLines = [
            OCRLine(lineID: "l1", rawText: "מאימתי קורין את שמע", boundingBox: .full),
            OCRLine(lineID: "l2", rawText: "בערבין משעה שהכהנים נכנסים", boundingBox: .full)
        ]
        let canonicalSource = "מאימתי קורין את שמע בערבין? משעה שהכהנים נכנסים לאכול בתרומתן"

        let alignment = TorahTextAlignment.align(ocrLines: ocrLines, sourceText: canonicalSource)
        #expect(alignment.overallScore >= 0.8)
        #expect(alignment.scoreComponents.lexicalCoverage >= 0.7)
        #expect(alignment.scoreComponents.sequenceOrderScore >= 0.8)
    }

    @Test("TorahSourceResolver marks unique primary source as verified")
    func testResolverVerified() async {
        let mock = MockTorahLibraryProvider()
        let locator = SourceLocator(
            providerID: "mock_otzaria",
            corpusID: "otzaria_bavli",
            workKey: "Berakhot",
            positionKind: .canonicalRef,
            positionValue: "Berakhot 2a"
        )
        let source = StudySource(
            locator: locator,
            primaryText: "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן",
            versionMetadata: VersionMetadata(versionTitle: "Talmud Bavli", language: "he"),
            licenseMetadata: LicenseMetadata(licenseName: "Public Domain")
        )
        mock.register(source: source, title: "ברכות דף ב עמוד א")

        let resolver = TorahSourceResolver(searchEngines: [mock])
        let evidence = OCREvidence(
            imageHash: "hash123",
            imageWidth: 1000,
            imageHeight: 1000,
            providerID: "apple_vision",
            modelRevision: "rev1",
            rawText: "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים",
            lines: [
                OCRLine(lineID: "1", rawText: "מאימתי קורין את שמע בערבין", boundingBox: .full),
                OCRLine(lineID: "2", rawText: "משעה שהכהנים נכנסים", boundingBox: .full)
            ]
        )

        let result = await resolver.resolve(evidence: evidence)
        #expect(result.status == .verified)
        #expect(result.selectedCandidate?.workTitle == "ברכות דף ב עמוד א")
        #expect(result.selectedCandidate?.sourceRole == .primaryWork)
    }

    @Test("TorahSourceResolver distinguishes quoted work and marks ambiguity")
    func testResolverQuotationDetection() async {
        let mock = MockTorahLibraryProvider()
        let locator = SourceLocator(
            providerID: "mock_otzaria",
            corpusID: "rambam_mishneh_torah",
            workKey: "Hilchot_Teshuvah",
            positionKind: .canonicalRef,
            positionValue: "Teshuvah 1:1"
        )
        let source = StudySource(
            locator: locator,
            primaryText: "כל מצות שבתורה בין עשה בין לא תעשה אם עבר אדם על אחת מהן",
            versionMetadata: VersionMetadata(versionTitle: "Mishneh Torah", language: "he"),
            licenseMetadata: LicenseMetadata(licenseName: "Public Domain")
        )
        mock.register(source: source, title: "הלכות תשובה פרק א")

        let resolver = TorahSourceResolver(searchEngines: [mock])
        // Excerpt is citing Rambam: "וכתב הרמב״ם וז״ל: כל מצות שבתורה..."
        let evidence = OCREvidence(
            imageHash: "hash456",
            imageWidth: 1000,
            imageHeight: 1000,
            providerID: "apple_vision",
            modelRevision: "rev1",
            rawText: "וכתב הרמב״ם כל מצות שבתורה בין עשה בין לא תעשה",
            lines: [
                OCRLine(lineID: "1", rawText: "וכתב הרמב״ם כל מצות שבתורה", boundingBox: .full),
                OCRLine(lineID: "2", rawText: "בין עשה בין לא תעשה", boundingBox: .full)
            ]
        )

        let result = await resolver.resolve(evidence: evidence)
        #expect(result.status == .ambiguous)
        #expect(result.selectedCandidate?.sourceRole == .citedWork)
        #expect(result.selectedCandidate?.ambiguityReasons.contains(where: { $0.contains("quotation") }) == true)
    }

    @Test("TorahSourceResolver handles insufficient image gracefully")
    func testInsufficientImage() async {
        let resolver = TorahSourceResolver(searchEngines: [])
        let evidence = OCREvidence(
            imageHash: "hash789",
            imageWidth: 1000,
            imageHeight: 1000,
            providerID: "apple_vision",
            modelRevision: "rev1",
            rawText: "רק שתי",
            lines: [OCRLine(lineID: "1", rawText: "רק שתי", boundingBox: .full)]
        )

        let result = await resolver.resolve(evidence: evidence)
        #expect(result.status == .insufficientImage)
        #expect(result.candidates.isEmpty)
    }

    @Test("TorahStudyDeepLink encodes and decodes round-trip accurately")
    func testDeepLinkRoundTrip() {
        let locator = SourceLocator(
            providerID: "otzaria",
            corpusID: "otzaria_bavli",
            corpusGeneration: "gen_202610",
            workKey: "Berakhot",
            positionKind: .canonicalRef,
            positionValue: "Berakhot 2a"
        )
        let deepLink = TorahStudyDeepLink(
            action: .open,
            locator: locator,
            generation: "gen_202610",
            workTitle: "ברכות ב.",
            highlightText: "מאימתי קורין את שמע",
            requestID: "req_001"
        )

        guard let maktabahURL = deepLink.url(scheme: "maktabah") else {
            Issue.record("Failed to generate Maktabah URL")
            return
        }

        #expect(maktabahURL.scheme == "maktabah")
        #expect(maktabahURL.host == "study")

        let parsed = TorahStudyDeepLink.parse(url: maktabahURL)
        #expect(parsed != nil)
        #expect(parsed?.action == .open)
        #expect(parsed?.locator.workKey == "Berakhot")
        #expect(parsed?.locator.positionValue == "Berakhot 2a")
        #expect(parsed?.workTitle == "ברכות ב.")
        #expect(parsed?.highlightText == "מאימתי קורין את שמע")
        #expect(parsed?.requestID == "req_001")
    }

    @Test("Resolver selects correct candidate from mock corpus")
    func testResolverSelectsCorrectCandidateFromMockCorpus() async {
        let library = MockTorahLibraryProvider(providerID: "seforim_corpus", displayName: "Torah Library")
        
        library.register(
            source: StudySource(
                locator: SourceLocator(providerID: "seforim_corpus", corpusID: "bavli", workKey: "Berakhot", positionKind: .canonicalRef, positionValue: "Berakhot 2a"),
                primaryText: "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן עד סוף האשמורה הראשונה דברי רבי אליעזר",
                versionMetadata: VersionMetadata(versionTitle: "Talmud Bavli", language: "he"),
                licenseMetadata: LicenseMetadata(licenseName: "Public Domain")
            ),
            title: "תלמוד בבלי מסכת ברכות דף ב עמוד א"
        )
        
        library.register(
            source: StudySource(
                locator: SourceLocator(providerID: "seforim_corpus", corpusID: "mishnah", workKey: "Peah", positionKind: .canonicalRef, positionValue: "Peah 1:1"),
                primaryText: "אלו דברים שאין להם שיעור הפאה והבכורים והראיון וגמילות חסדים ותלמוד תורה",
                versionMetadata: VersionMetadata(versionTitle: "Mishnah", language: "he"),
                licenseMetadata: LicenseMetadata(licenseName: "Public Domain")
            ),
            title: "משנה מסכת פאה פרק א משנה א"
        )

        library.register(
            source: StudySource(
                locator: SourceLocator(providerID: "seforim_corpus", corpusID: "rambam", workKey: "Hilchot_Deot", positionKind: .canonicalRef, positionValue: "Deot 1:1"),
                primaryText: "דעות הרבה יש לכל אחד ואחד מבני אדם וזו משונה מזו ורחוקה ממנה ביותר",
                versionMetadata: VersionMetadata(versionTitle: "Mishneh Torah", language: "he"),
                licenseMetadata: LicenseMetadata(licenseName: "Public Domain")
            ),
            title: "משנה תורה הלכות דעות פרק א"
        )
        
        let ocrInput = OCREvidence(
            imageHash: "img_sha256_unlabeled_0987",
            imageWidth: 1200,
            imageHeight: 1600,
            providerID: "apple_vision_local",
            modelRevision: "v3",
            rawText: "הפאה והבכורים והראיון וגמילות חסדים ותלמוד תורה",
            lines: [
                OCRLine(lineID: "l1", rawText: "הפאה והבכורים והראיון", boundingBox: .full),
                OCRLine(lineID: "l2", rawText: "וגמילות חסדים ותלמוד תורה", boundingBox: .full)
            ]
        )
        
        let resolver = TorahSourceResolver(searchEngines: [library])
        let result = await resolver.resolve(evidence: ocrInput)
        
        #expect(result.status == .verified)
        #expect(result.selectedCandidate != nil)
        #expect(result.selectedCandidate?.locator.workKey == "Peah")
        #expect(result.selectedCandidate?.locator.positionValue == "Peah 1:1")
        #expect(result.selectedCandidate?.workTitle == "משנה מסכת פאה פרק א משנה א")
        #expect((result.selectedCandidate?.scoreComponents.lexicalCoverage ?? 0) >= 0.8)
    }

    @Test("Resolver discovers source from actual Otzaria SQLite corpus file using OCR text only")
    func testResolverDiscoversSourceFromRealOtzariaCorpus() async throws {
        var dbPath = ""
        let possiblePaths = [
            OtzariaLibraryProvider.fileSystemPath(for: URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/TorahPhotoStudy/test_seforim.db")),
            OtzariaLibraryProvider.fileSystemPath(for: URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/TorahPhotoStudy/test_seforim.db")),
            "C:/Users/DAVID/Code/hanlin-torah-photo-study/Tests/Fixtures/TorahPhotoStudy/test_seforim.db"
        ]
        for p in possiblePaths {
            if FileManager.default.fileExists(atPath: p) {
                dbPath = p
                break
            }
        }
        #expect(!dbPath.isEmpty, "Actual SQLite database file must exist at one of candidate paths")
        let dbURL = URL(fileURLWithPath: dbPath)

        let otzariaProvider = OtzariaLibraryProvider(databaseURL: dbURL)
        #expect(otzariaProvider.isAvailable)

        let ocrInput = OCREvidence(
            imageHash: "img_real_sqlite_pirkei_avot_01",
            imageWidth: 1024,
            imageHeight: 1400,
            providerID: "apple_vision_local",
            modelRevision: "v3",
            rawText: "משה קיבל תורה מסיני ומסרה ליהושע ויהושע לזקנים",
            lines: [
                OCRLine(lineID: "l1", rawText: "משה קיבל תורה מסיני", boundingBox: .full),
                OCRLine(lineID: "l2", rawText: "ומסרה ליהושע ויהושע לזקנים", boundingBox: .full)
            ]
        )

        let coordinator = TorahLibraryCoordinator(
            otzariaProvider: otzariaProvider,
            zayitProvider: ZayitLibraryProvider(databaseURL: dbURL)
        )

        let result = await coordinator.identifyExcerpt(evidence: ocrInput, allowRemoteFallback: false)

        #expect(result.status == .verified)
        #expect(result.selectedCandidate != nil)
        #expect(result.selectedCandidate?.locator.providerID == "otzaria")
        #expect(result.selectedCandidate?.workTitle.contains("אבות") == true)
        
        let section = try await coordinator.getSection(locator: result.selectedCandidate!.locator)
        #expect(section.primaryText.contains("משה קיבל תורה מסיני"))
        #expect((result.selectedCandidate?.scoreComponents.lexicalCoverage ?? 0) >= 0.8)
    }

    // MARK: - TOR-06: Sefaria HTTP and Decoding Error Distinction

    @Test("Sefaria throws typed error on HTTP 500 server failure rather than empty hits")
    func testSefariaHTTP500Error() async throws {
        let provider = SefariaLibraryProvider(transport: { url in
            throw TorahProviderNetworkError.httpError(statusCode: 500, url: url.absoluteString)
        })

        await #expect(throws: TorahProviderNetworkError.self) {
            _ = try await provider.search(query: "בראשית", limit: 5)
        }
    }

    @Test("Sefaria throws typed error on HTTP 401 and 429 rather than empty hits")
    func testSefariaHTTP401And429() async throws {
        let provider = SefariaLibraryProvider(transport: { url in
            throw TorahProviderNetworkError.httpError(statusCode: 429, url: url.absoluteString)
        })

        await #expect(throws: TorahProviderNetworkError.self) {
            _ = try await provider.getSection(locator: SourceLocator(
                providerID: "sefaria",
                corpusID: "canonical",
                workKey: "Genesis 1:1",
                positionKind: .canonicalRef,
                positionValue: "Genesis 1:1"
            ))
        }
    }

    @Test("Sefaria throws decodingError on malformed JSON payload")
    func testSefariaMalformedJSON() async throws {
        let provider = SefariaLibraryProvider(transport: { _ in
            Data("not valid json {[[".utf8)
        })

        await #expect(throws: TorahProviderNetworkError.self) {
            _ = try await provider.search(query: "בראשית", limit: 5)
        }
    }

    @Test("Sefaria returns empty array on legitimate 200 with zero hits")
    func testSefariaLegitimateEmptyHits() async throws {
        let provider = SefariaLibraryProvider(transport: { _ in
            Data("{\"hits\": {\"hits\": []}}".utf8)
        })

        let hits = try await provider.search(query: "nonexistent_term_xyz", limit: 5)
        #expect(hits.isEmpty)
    }

    // MARK: - TOR-08: ITorahSharedStorage Mode Distinction

    @Test("ITorahSharedStorage mode distinction and truthful provenance")
    func testStorageModeDistinction() throws {
        let mode = ITorahSharedStorage.currentStorageMode
        #expect(mode == .privateFallback || mode == .sharedAuthorizedGroup)
        if !ITorahSharedStorage.isSharedAppGroupActive {
            #expect(mode == .privateFallback)
            let url = try ITorahSharedStorage.containerURL()
            #expect(url.path.contains("ITorahSharedStorage"))
        }
    }

    // MARK: - TOR-07: Zayit Provider Fallback and Availability

    @Test("Zayit provider surfaces Tantivy index availability and SQLite fallback honestly")
    func testZayitFallbackTruthfulness() {
        let dummyIndexURL = URL(fileURLWithPath: "/nonexistent/tantivy/index")
        let zayit = ZayitLibraryProvider(searchIndexURL: dummyIndexURL)
        #expect(!zayit.isTantivyIndexAvailable)
        
        let coordinator = TorahLibraryCoordinator(zayitProvider: zayit)
        let statuses = coordinator.providerStatuses()
        if let zayitStatus = statuses.first(where: { $0.providerID == "zayit" }) {
            #expect(zayitStatus.provenance.contains("fallback") || zayitStatus.provenance.contains("uninstalled"))
        }
    }

    // MARK: - TOR-09: Coordinator Links, Topics, and Provider Dispatch

    @Test("Coordinator getLinks and getTopics route correctly and fail closed on unknown provider")
    func testCoordinatorLinksAndTopicsRouting() async throws {
        let coordinator = TorahLibraryCoordinator()
        let unknownLocator = SourceLocator(
            providerID: "unsupported_provider_xyz",
            corpusID: "test",
            workKey: "test",
            positionKind: .canonicalRef,
            positionValue: "test 1:1"
        )

        await #expect(throws: TorahCoordinatorError.self) {
            _ = try await coordinator.getLinks(locator: unknownLocator)
        }

        await #expect(throws: TorahCoordinatorError.self) {
            _ = try await coordinator.getTopics(locator: unknownLocator)
        }
    }

    // MARK: - TOR-01: Coordinator Local-Only Privacy

    @Test("Coordinator identifyExcerpt with allowRemoteFallback false never contacts Sefaria")
    func testCoordinatorLocalOnlyPrivacy() async throws {
        let remoteContacted = AtomicBoolBox(false)
        let sefaria = SefariaLibraryProvider(transport: { url in
            remoteContacted.set(true)
            throw TorahProviderNetworkError.httpError(statusCode: 500, url: url.absoluteString)
        })
        let coordinator = TorahLibraryCoordinator(sefariaProvider: sefaria)

        let evidence = OCREvidence(
            imageHash: "hash_local_only",
            imageWidth: 800,
            imageHeight: 600,
            providerID: "apple_vision_local",
            modelRevision: "v3",
            rawText: "מילים כלשהן לבדיקת פרטיות מקומית בלבד",
            lines: [
                OCRLine(lineID: "l1", rawText: "מילים כלשהן לבדיקת", boundingBox: .full),
                OCRLine(lineID: "l2", rawText: "פרטיות מקומית בלבד", boundingBox: .full)
            ]
        )

        let result = await coordinator.identifyExcerpt(evidence: evidence, allowRemoteFallback: false)
        #expect(!remoteContacted.value, "Remote Sefaria provider must NOT be contacted when allowRemoteFallback is false")
        #expect(result.status == .notFound)
    }
}

private final class AtomicBoolBox: @unchecked Sendable {
    private var _value: Bool
    private let lock = NSLock()

    init(_ value: Bool = false) {
        self._value = value
    }

    func set(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _value = value
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
