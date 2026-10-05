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

    @Test("Resolver discovers source from corpus using OCR text only with no expected title or ref")
    func testResolverDiscoversSourceFromCorpusUsingOCRTextOnly() async {
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
}
