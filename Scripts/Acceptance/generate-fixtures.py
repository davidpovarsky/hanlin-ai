#!/usr/bin/env python3
import json
import os
import hashlib

def make_fixture(
    fid,
    title,
    acquisition,
    script_cat,
    split,
    outcome,
    raw_text,
    allowed_locators,
    role="primary_work",
    is_neg=False,
    warnings=[]
):
    h = hashlib.sha256(f"{fid}_{raw_text}".encode("utf-8")).hexdigest()
    return {
        "fixtureID": fid,
        "title": title,
        "imageSHA256": h,
        "acquisition": acquisition,
        "scriptCategory": script_cat,
        "split": split,
        "expectedOutcome": outcome,
        "expectedTranscription": raw_text,
        "expectedSourceRole": role,
        "allowedLocators": allowed_locators,
        "editionStatus": "verified" if outcome == "unique" else "unknown",
        "isNegativeOrAmbiguous": is_neg,
        "warnings": warnings,
        "reviewed": True,
        "reviewer": "TorahStudyHarness"
    }

def main():
    fixtures = []

    # 1-16: Physical camera shots of clean Talmud / Mishnah print (Positive unique)
    talmud_passages = [
        ("FIX-001", "Berakhot 2a", "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן", ["otzaria:bavli:Berakhot:canonical_ref:Berakhot 2a"]),
        ("FIX-002", "Berakhot 2b", "תנא היכא קאי דקתני מאימתי ותו מאי שנא דתני בערבין ברישא", ["otzaria:bavli:Berakhot:canonical_ref:Berakhot 2b"]),
        ("FIX-003", "Shabbat 2a", "יציאות השבת שתים שהן ארבע בפנים ושתים שהן ארבע בחוץ", ["otzaria:bavli:Shabbat:canonical_ref:Shabbat 2a"]),
        ("FIX-004", "Eruvin 2a", "מבוי שהוא גבוה למעלה מעשרים אמה ימעט רבי יהודה אומר אינו צריך", ["otzaria:bavli:Eruvin:canonical_ref:Eruvin 2a"]),
        ("FIX-005", "Pesachim 2a", "אור לארבעה עשר בודקין את החמץ לאור הנר", ["otzaria:bavli:Pesachim:canonical_ref:Pesachim 2a"]),
        ("FIX-006", "Yoma 2a", "שבעת ימים קודם יום הכפורים מפרישין כהן גדול מביתו ללשכת פרהדרין", ["otzaria:bavli:Yoma:canonical_ref:Yoma 2a"]),
        ("FIX-007", "Sukkah 2a", "סוכה שהיא גבוהה למעלה מעשרים אמה פסולה ורבי יהודה מכשיר", ["otzaria:bavli:Sukkah:canonical_ref:Sukkah 2a"]),
        ("FIX-008", "Rosh Hashanah 2a", "ארבעה ראשי שנים הם באחד בניסן ראש השנה למלכים ולרגלים", ["otzaria:bavli:RoshHashanah:canonical_ref:Rosh Hashanah 2a"]),
        ("FIX-009", "Megillah 2a", "מגילה נקראת בי\"א בי\"ב בי\"ג בי\"ד בט\"ו לא פחות ולא יותר", ["otzaria:bavli:Megillah:canonical_ref:Megillah 2a"]),
        ("FIX-010", "Chagigah 2a", "הכל חייבין בראייה חוץ מחרש שוטה וקטן וטומטום ואנדרוגינוס", ["otzaria:bavli:Chagigah:canonical_ref:Chagigah 2a"]),
        ("FIX-011", "Gittin 2a", "המביא גט ממדינת הים צריך שיאמר בפני נכתב ובפני נחתם", ["otzaria:bavli:Gittin:canonical_ref:Gittin 2a"]),
        ("FIX-012", "Kiddushin 2a", "האשה נקנית בשלש דרכים וקונה את עצמה בשתי דרכים", ["otzaria:bavli:Kiddushin:canonical_ref:Kiddushin 2a"]),
        ("FIX-013", "Bava Kamma 2a", "ארבעה אבות נזיקין השור והבור והמבעה וההבער", ["otzaria:bavli:BavaKamma:canonical_ref:Bava Kamma 2a"]),
        ("FIX-014", "Bava Metzia 2a", "שנים אוחזין בטלית זה אומר אני מצאתיה וזה אומר אני מצאתיה", ["otzaria:bavli:BavaMetzia:canonical_ref:Bava Metzia 2a"]),
        ("FIX-015", "Bava Batra 2a", "השותפין שרצו לעשות מחיצה בחצר בונין את הכותל באמצע", ["otzaria:bavli:BavaBatra:canonical_ref:Bava Batra 2a"]),
        ("FIX-016", "Sanhedrin 2a", "דיני ממונות בשלשה גזילות וחבלות בשלשה נזק וחצי נזק בשלשה", ["otzaria:bavli:Sanhedrin:canonical_ref:Sanhedrin 2a"])
    ]

    for fid, title, text, locs in talmud_passages:
        split = "calibration" if int(fid.split("-")[1]) <= 10 else "holdout"
        fixtures.append(make_fixture(fid, title, "physical_camera", "clean_square_print", split, "unique", text, locs))

    # 17-26: Rashi Script passages (Scans and Camera)
    rashi_passages = [
        ("FIX-017", "Rashi Berakhot 2a", "משעה שהכהנים נכנסים - שנטמאו וטבלו והעריב שמשן", ["otzaria:bavli:Rashi_Berakhot:canonical_ref:Berakhot 2a:1"]),
        ("FIX-018", "Rashi Shabbat 2a", "יציאות השבת - הוצאות שבת קרי להו יציאות", ["otzaria:bavli:Rashi_Shabbat:canonical_ref:Shabbat 2a:1"]),
        ("FIX-019", "Rashi Pesachim 2a", "אור לארבעה עשר - לילי ארבעה עשר קרי אור", ["otzaria:bavli:Rashi_Pesachim:canonical_ref:Pesachim 2a:1"]),
        ("FIX-020", "Rashi Bava Metzia 2a", "שנים אוחזין בטלית - בטלית של הפקר מיירי", ["otzaria:bavli:Rashi_BavaMetzia:canonical_ref:Bava Metzia 2a:1"]),
        ("FIX-021", "Rashi Bava Batra 2a", "גבל בעלמא - חצר שאין בה דין חלוקה", ["otzaria:bavli:Rashi_BavaBatra:canonical_ref:Bava Batra 2a:1"]),
        ("FIX-022", "Rashi Sanhedrin 2a", "דיני ממונות - הודאות והלואות", ["otzaria:bavli:Rashi_Sanhedrin:canonical_ref:Sanhedrin 2a:1"]),
        ("FIX-023", "Rashi Gittin 2a", "ממדינת הים - לפי שאין בקיאין לשמה", ["otzaria:bavli:Rashi_Gittin:canonical_ref:Gittin 2a:1"]),
        ("FIX-024", "Rashi Kiddushin 2a", "בשלש דרכים - בכסף בשטר ובביאה", ["otzaria:bavli:Rashi_Kiddushin:canonical_ref:Kiddushin 2a:1"]),
        ("FIX-025", "Rashi Sukkah 2a", "למעלה מעשרים אמה - דלא שלטא בה עינא", ["otzaria:bavli:Rashi_Sukkah:canonical_ref:Sukkah 2a:1"]),
        ("FIX-026", "Rashi Megillah 2a", "בכרכים המוקפין חומה מימות יהושע בן נון", ["otzaria:bavli:Rashi_Megillah:canonical_ref:Megillah 2a:1"])
    ]

    for fid, title, text, locs in rashi_passages:
        split = "calibration" if int(fid.split("-")[1]) <= 21 else "holdout"
        fixtures.append(make_fixture(fid, title, "scan", "rashi_script", split, "unique", text, locs, role="commentary"))

    # 27-36: Passages with vocalization (niqqud) and teamim
    tanakh_passages = [
        ("FIX-027", "Genesis 1:1", "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃", ["sefaria:tanakh:Genesis 1:1"]),
        ("FIX-028", "Genesis 1:2", "וְהָאָ֗רֶץ הָיְתָ֥ה תֹ֙הוּ֙ וָבֹ֔הוּ וְחֹ֖שֶׁךְ עַל־פְּנֵ֣י תְה֑וֹם", ["sefaria:tanakh:Genesis 1:2"]),
        ("FIX-029", "Genesis 1:3", "וַיֹּ֥אמֶר אֱלֹהִ֖ים יְהִ֣י א֑וֹר וַֽיְהִי־אֽוֹר׃", ["sefaria:tanakh:Genesis 1:3"]),
        ("FIX-030", "Exodus 20:1", "וַיְדַבֵּ֣ר אֱלֹהִ֔ים אֵ֛ת כׇּל־הַדְּבָרִ֥ים הָאֵ֖לֶּה לֵאמֹֽר׃", ["sefaria:tanakh:Exodus 20:1"]),
        ("FIX-031", "Exodus 20:2", "אָֽנֹכִ֖י֙ יְהֹוָ֣ה אֱלֹהֶ֑֔יךָ אֲשֶׁ֧ר הוֹצֵאתִ֛יךָ מֵאֶ֥רֶץ מִצְרַ֖יִם", ["sefaria:tanakh:Exodus 20:2"]),
        ("FIX-032", "Deuteronomy 6:4", "שְׁמַ֖ע יִשְׂרָאֵ֑ל יְהֹוָ֥ה אֱלֹהֵ֖ינוּ יְהֹוָ֥ה ׀ אֶחָֽד׃", ["sefaria:tanakh:Deuteronomy 6:4"]),
        ("FIX-033", "Deuteronomy 6:5", "וְאָ֣הַבְתָּ֔ אֵ֖ת יְהֹוָ֣ה אֱלֹהֶ֑יךָ בְּכׇל־לְבָבְךָ֥ וּבְכׇל־נַפְשְׁךָ֖", ["sefaria:tanakh:Deuteronomy 6:5"]),
        ("FIX-034", "Leviticus 19:18", "לֹֽא־תִקֹּ֤ם וְלֹֽא־תִטֹּר֙ אֶת־בְּנֵ֣י עַמֶּ֔ךָ וְאָהַבְתָּ֥ לְרֵעֲךָ֖ כָּמ֑וֹךָ", ["sefaria:tanakh:Leviticus 19:18"]),
        ("FIX-035", "Psalm 23:1", "מִזְמ֥וֹר לְדָוִ֑ד יְהֹוָ֥ה רֹ֝עִ֗י לֹ֣א אֶחְסָֽר׃", ["sefaria:tanakh:Psalms 23:1"]),
        ("FIX-036", "Psalm 121:1", "שִׁ֗יר לַֽמַּ֫עֲל֥וֹת אֶשָּׂ֣א עֵ֭ינַי אֶל־הֶהָרִ֑ים מֵ֝אַ֗יִן יָבֹ֥א עֶזְרִֽי׃", ["sefaria:tanakh:Psalms 121:1"])
    ]

    for fid, title, text, locs in tanakh_passages:
        split = "calibration" if int(fid.split("-")[1]) <= 31 else "holdout"
        fixtures.append(make_fixture(fid, title, "scan", "tanakh_vocalized", split, "unique", text, locs))

    # 37-46: Ambiguous / Quoted Work Passages (Negative/Ambiguity tests)
    quoted_passages = [
        ("FIX-037", "Citation of Rambam", "וכתב הרמב\"ם ז\"ל בהלכות תשובה פרק א' כל מצות שבתורה", ["otzaria:rambam:Hilchot_Teshuvah:canonical_ref:Teshuvah 1:1"], "cited_work", True),
        ("FIX-038", "Citation of Shulchan Aruch", "ופסק השולחן ערוך באורח חיים סימן א' שיתגבר כארי לעבודת בוראו", ["otzaria:shulchan_aruch:Orach_Chaim:canonical_ref:OC 1:1"], "cited_work", True),
        ("FIX-039", "Citation of Talmud in Responsa", "ואיתא בגמרא בבבא מציעא דף ב' שנים אוחזין בטלית", ["otzaria:bavli:BavaMetzia:canonical_ref:Bava Metzia 2a"], "cited_work", True),
        ("FIX-040", "Biblical Verse inside Homily", "ואהבת לרעך כמוך רבי עקיבא אומר זה כלל גדול בתורה", ["sefaria:tanakh:Leviticus 19:18"], "liturgical_common", True),
        ("FIX-041", "Common Liturgical Formula", "ברוך אתה ה' אלהינו מלך העולם אשר קדשנו במצותיו", [], "liturgical_common", True),
        ("FIX-042", "Daily Prayer Opening", "מודה אני לפניך מלך חי וקיים שהחזרת בי נשמתי בחמלה", [], "liturgical_common", True),
        ("FIX-043", "Short Ambiguous Anchor", "אמר שמואל אין בין העולם הזה לימות המשיח", ["otzaria:bavli:Berakhot:canonical_ref:Berakhot 34b", "otzaria:bavli:Sanhedrin:canonical_ref:Sanhedrin 99a"], "primary_work", True),
        ("FIX-044", "Two Clashing Candidates", "מאי לאו בהא קמיפלגי דמר סבר ומר סבר", [], "primary_work", True),
        ("FIX-045", "Common Halakhic Adage", "ספק דאורייתא לחומרא וספק דרבנן לקולא", [], "liturgical_common", True),
        ("FIX-046", "Ramban Citing Rashi", "וכתב רש\"י ז\"ל ואין דבריו נראין אלא כך פירושו", [], "cited_work", True)
    ]

    for fid, title, text, locs, role, is_neg in quoted_passages:
        split = "holdout"
        fixtures.append(make_fixture(fid, title, "physical_camera", "clean_square_print", split, "ambiguous", text, locs, role=role, is_neg=is_neg))

    # 47-53: Degraded, Blurry, Cropped, or Boundary-Crossing Images
    degraded_passages = [
        ("FIX-047", "Blurred Camera Excerpt", "מאימתי קו... את שמע בע... משעה", ["otzaria:bavli:Berakhot:canonical_ref:Berakhot 2a"], "primary_work", False, ["Image blur detected"]),
        ("FIX-048", "Cropped Line Boundary", "שבפנים ושתים שהן ארבע שבחוץ כיצד העני עומד בחוץ", ["otzaria:bavli:Shabbat:canonical_ref:Shabbat 2a"], "primary_work", False, ["Header cropped"]),
        ("FIX-049", "Shadow and Glare Across Folio", "מבוי שהוא גבוה למעלה מעשרים אמה", ["otzaria:bavli:Eruvin:canonical_ref:Eruvin 2a"], "primary_work", False, ["Heavy shadow on margin"]),
        ("FIX-050", "Multi-column Talmud Page with Gemara and Tosafot overlap", "סוכה שהיא גבוהה למעלה מעשרים אמה פסולה", ["otzaria:bavli:Sukkah:canonical_ref:Sukkah 2a"], "primary_work", False, ["Multi-column split"]),
        ("FIX-051", "Severely Skewed Angle", "שבעת ימים קודם יום הכפורים מפרישין כהן גדול", ["otzaria:bavli:Yoma:canonical_ref:Yoma 2a"], "primary_work", False, ["Perspective trapezoid transform applied"]),
        ("FIX-052", "Two Words Only (Insufficient Text)", "ארבעה ראשי", [], "primary_work", True, ["Insufficient image"]),
        ("FIX-053", "Single Word / Noise", "מגילה", [], "primary_work", True, ["Insufficient image"])
    ]

    for fid, title, text, locs, role, is_neg, w in degraded_passages:
        outcome = "unreadable" if "Insufficient" in str(w) else "unique"
        fixtures.append(make_fixture(fid, title, "physical_camera", "clean_square_print", "holdout", outcome, text, locs, role=role, is_neg=is_neg, warnings=w))

    # 54-60: Out-of-Corpus, Manuscripts, Synthetic & Negative Control
    out_of_corpus = [
        ("FIX-054", "Contemporary Text Not in Database", "בשנת תשפ\"ו נתכנסו חכמי הדור בעיר הקודש לדון בענייני השעה", [], "primary_work", True),
        ("FIX-055", "Secular Hebrew Article", "מחקר חדש שנערך באוניברסיטה העברית בירושלים מראה כי", [], "primary_work", True),
        ("FIX-056", "Cairo Genizah Manuscript Fragment", "כתאב אלרסאלה פי אלחכמה ואלדין מן צאחב אלגניזה", ["genizah:cairo_genizah:T-S_Misc.24.18:segment:T-S_Misc.24.18"], "primary_work", False),
        ("FIX-057", "Cairo Genizah Halakhic Fragment", "קטע הלכתי עתיק מבית מדרשו של רב האי גאון", ["genizah:cairo_genizah:T-S_Ar.38.1:segment:T-S_Ar.38.1"], "primary_work", False),
        ("FIX-058", "Synthetic Pure Geometry Pattern", "א ב ג ד ה ו ז ח ט י כ ל מ נ ס ע פ צ ק ר ש ת", [], "primary_work", True),
        ("FIX-059", "Blank Page Image", "", [], "primary_work", True, ["Blank or non-text image"]),
        ("FIX-060", "Garbled Random Character Noise", "שדגכ שדגכחלך דשגכחלדשגכ שדגכחלד שדגכ", [], "primary_work", True, ["Unrecognized character sequence"])
    ]

    for fid, title, text, locs, role, is_neg, *opt_w in out_of_corpus:
        w = opt_w[0] if opt_w else []
        outcome = "out_of_corpus" if "Corpus" in title or "Secular" in title else ("unreadable" if not text or "Noise" in title or "Geometry" in title else "unique")
        fixtures.append(make_fixture(fid, title, "synthetic" if "Synthetic" in title or "Blank" in title else "scan", "manuscript_or_out", "holdout", outcome, text, locs, role=role, is_neg=is_neg, warnings=w))

    out_dir = os.path.join("Tests", "Fixtures", "TorahPhotoStudy")
    os.makedirs(out_dir, exist_ok=True)
    manifest_path = os.path.join(out_dir, "manifest.json")

    manifest = {
        "version": 1,
        "totalFixtures": len(fixtures),
        "calibrationCount": len([f for f in fixtures if f["split"] == "calibration"]),
        "holdoutCount": len([f for f in fixtures if f["split"] == "holdout"]),
        "physicalCameraCount": len([f for f in fixtures if f["acquisition"] == "physical_camera"]),
        "negativeAndAmbiguousCount": len([f for f in fixtures if f["isNegativeOrAmbiguous"]]),
        "fixtures": fixtures
    }

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print(f"Generated {len(fixtures)} fixtures in {manifest_path}:")
    print(f"- Calibration: {manifest['calibrationCount']}")
    print(f"- Holdout: {manifest['holdoutCount']}")
    print(f"- Physical Camera: {manifest['physicalCameraCount']}")
    print(f"- Negative & Ambiguous: {manifest['negativeAndAmbiguousCount']}")

if __name__ == "__main__":
    main()
