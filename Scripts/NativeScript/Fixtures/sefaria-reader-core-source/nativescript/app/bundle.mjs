// ============================================================================
// Sefaria Jewish Library & Texts MiniApp for Hanlin AI
// @nativescript/core version of the existing direct-UIKit NativeScript MiniApp.
//
// Main UI, layout, navigation, HTTP and controls use @nativescript/core.
// No QuickJS, Hanlin ScriptUI, or effects/RPC layer is involved.
// ============================================================================

import {
  ActivityIndicator,
  Application,
  Button,
  Color,
  Frame,
  Http,
  Label,
  Page,
  ScrollView,
  SegmentedBar,
  SegmentedBarItem,
  StackLayout,
  TabView,
  TabViewItem,
  TextField,
  WrapLayout,
} from "@nativescript/core";

// ----------------------------------------------------------------------------
// 1. Theme and small Core helpers
// ----------------------------------------------------------------------------

const C = {
  page: new Color("#F2F2F7"),
  card: new Color("#FFFFFF"),
  cardSecondary: new Color("#F7F7FA"),
  label: new Color("#111111"),
  secondary: new Color("#6B7280"),
  blue: new Color("#0A84FF"),
  blueSoft: new Color("#E7F1FF"),
  indigo: new Color("#5856D6"),
  indigoSoft: new Color("#EFEEFF"),
  gray5: new Color("#E5E5EA"),
  gray6: new Color("#F2F2F7"),
  red: new Color("#FF3B30"),
  white: new Color("#FFFFFF"),
};

function cleanHtml(raw) {
  if (!raw) return "";
  return String(raw).replace(/<[^>]+>/g, "").trim();
}

function makeLabel(text, options = {}) {
  const label = new Label();
  label.text = text ?? "";
  label.textWrap = options.wrap !== false;
  label.color = options.color || C.label;
  label.fontSize = options.fontSize || 15;
  if (options.bold) label.fontWeight = "700";
  if (options.align) label.textAlignment = options.align;
  if (options.marginTop != null) label.marginTop = options.marginTop;
  if (options.marginBottom != null) label.marginBottom = options.marginBottom;
  return label;
}

function makeCard(padding = 16) {
  const card = new StackLayout();
  card.backgroundColor = C.card;
  card.borderRadius = 16;
  card.padding = padding;
  card.marginBottom = 12;
  return card;
}

function makeBadge(text, color = C.blue, background = C.blueSoft) {
  const label = makeLabel(text, { fontSize: 11, bold: true, color });
  label.backgroundColor = background;
  label.borderRadius = 8;
  label.padding = "4 8";
  label.horizontalAlignment = "left";
  return label;
}

function makeButton(text, onTap, options = {}) {
  const button = new Button();
  button.text = text;
  if (options.identifier) {
    button.accessibilityIdentifier = options.identifier;
    button.automationText = options.identifier;
  }
  button.fontSize = options.fontSize || 14;
  button.fontWeight = options.bold === false ? "400" : "600";
  button.height = options.height || 42;
  button.padding = options.padding || "7 12";
  button.borderRadius = options.radius || 10;
  button.backgroundColor = options.background || C.blue;
  button.color = options.color || C.white;
  button.marginTop = options.marginTop || 0;
  button.marginBottom = options.marginBottom || 0;
  button.on("tap", onTap);
  return button;
}

function makeChip(text, onTap) {
  const button = makeButton(text, onTap, {
    background: C.gray5,
    color: C.label,
    fontSize: 12,
    height: 36,
    radius: 8,
    padding: "4 10",
  });
  button.marginRight = 6;
  button.marginBottom = 6;
  return button;
}

function makeSpinner() {
  const spinner = new ActivityIndicator();
  spinner.busy = false;
  spinner.width = 32;
  spinner.height = 32;
  spinner.horizontalAlignment = "center";
  spinner.margin = 12;
  return spinner;
}

function clearLayout(layout) {
  layout.removeChildren();
}

function makeScrollPage(title) {
  const page = new Page();
  page.backgroundColor = C.page;
  page.actionBar.title = title;

  const scroll = new ScrollView();
  const content = new StackLayout();
  content.padding = 16;
  content.horizontalAlignment = "stretch";
  scroll.content = content;
  page.content = scroll;

  return { page, content };
}

function makeSectionTitle(title, subtitle = null, color = C.blue) {
  const card = makeCard(18);
  card.addChild(makeLabel(title, {
    fontSize: 19,
    bold: true,
    color,
    align: "right",
    marginBottom: subtitle ? 5 : 0,
  }));
  if (subtitle) {
    card.addChild(makeLabel(subtitle, {
      fontSize: 14,
      color: C.secondary,
      align: "right",
    }));
  }
  return card;
}

// ----------------------------------------------------------------------------
// 2. Sefaria API client — using @nativescript/core Http
// ----------------------------------------------------------------------------

const API_BASE = "https://www.sefaria.org/api";
const apiCache = new Map();

async function httpJSON(url) {
  if (apiCache.has(url)) return apiCache.get(url);
  const data = await Http.getJSON(url);
  apiCache.set(url, data);
  return data;
}

const SefariaService = {
  getCalendars() {
    return httpJSON(`${API_BASE}/calendars`);
  },

  getIndex() {
    return httpJSON(`${API_BASE}/index`);
  },

  getText(ref) {
    const cleanRef = encodeURIComponent(String(ref || "").trim());
    return httpJSON(`${API_BASE}/texts/${cleanRef}?context=0&stripItags=1`);
  },

  searchName(query) {
    const q = encodeURIComponent(String(query || "").trim());
    return httpJSON(`${API_BASE}/name/${q}`);
  },

  getLexicon(word) {
    const w = encodeURIComponent(String(word || "").trim());
    return httpJSON(`${API_BASE}/words/${w}`);
  },
};

// ----------------------------------------------------------------------------
// 3. Reader Page
// ----------------------------------------------------------------------------

function createReaderPage(frame, refString, customTitle) {
  const { page, content } = makeScrollPage(customTitle || refString || "קורא מקורות");

  let currentLanguageMode = 0; // 0 Hebrew, 1 English, 2 bilingual
  let currentFontSize = 18;
  let textData = null;

  const controlsCard = makeCard(14);

  const topRow = new StackLayout();
  topRow.orientation = "horizontal";
  topRow.marginBottom = 10;
  const backBtn = makeButton("חזרה", () => {
    if (typeof frame?.canGoBack === "function") {
      if (frame.canGoBack()) {
        frame.goBack();
      }
    } else if (frame?.goBack) {
      frame.goBack();
    }
  }, {
    background: C.gray5,
    color: C.label,
    height: 34,
    fontSize: 13,
    bold: true,
    identifier: "sefaria-reader-back",
  });
  backBtn.width = "25%";
  topRow.addChild(backBtn);
  controlsCard.addChild(topRow);

  const languageControl = new SegmentedBar();
  const heItem = new SegmentedBarItem();
  heItem.title = "עברית";
  const enItem = new SegmentedBarItem();
  enItem.title = "English";
  const bothItem = new SegmentedBarItem();
  bothItem.title = "דו-לשוני";
  languageControl.items = [heItem, enItem, bothItem];
  languageControl.selectedIndex = 0;
  controlsCard.addChild(languageControl);

  const fontRow = new StackLayout();
  fontRow.orientation = "horizontal";
  fontRow.marginTop = 10;

  const fontLabel = makeLabel(`גודל כתב: ${currentFontSize}pt`, {
    fontSize: 13,
    color: C.secondary,
  });
  fontLabel.verticalAlignment = "middle";
  fontLabel.width = "55%";

  const minus = makeButton("A−", () => {
    if (currentFontSize <= 13) return;
    currentFontSize -= 2;
    fontLabel.text = `גודל כתב: ${currentFontSize}pt`;
    renderVerses();
  }, { background: C.gray5, color: C.label, height: 36, fontSize: 13 });
  minus.width = "20%";
  minus.marginRight = 6;

  const plus = makeButton("A+", () => {
    if (currentFontSize >= 34) return;
    currentFontSize += 2;
    fontLabel.text = `גודל כתב: ${currentFontSize}pt`;
    renderVerses();
  }, { background: C.gray5, color: C.label, height: 36, fontSize: 13 });
  plus.width = "20%";

  fontRow.addChild(fontLabel);
  fontRow.addChild(minus);
  fontRow.addChild(plus);
  controlsCard.addChild(fontRow);
  content.addChild(controlsCard);

  const verses = new StackLayout();
  content.addChild(verses);

  const spinner = makeSpinner();
  spinner.busy = true;
  content.addChild(spinner);

  languageControl.on("selectedIndexChanged", () => {
    currentLanguageMode = languageControl.selectedIndex;
    renderVerses();
  });

  function renderVerses() {
    if (!textData) return;
    clearLayout(verses);

    const hebrewVerses = Array.isArray(textData.he)
      ? textData.he
      : [textData.he].filter(Boolean);
    const englishVerses = Array.isArray(textData.text)
      ? textData.text
      : [textData.text].filter(Boolean);
    const count = Math.max(hebrewVerses.length, englishVerses.length);

    if (!count) {
      verses.addChild(makeLabel("לא נמצאו קטעי טקסט עבור מראה מקום זה.", {
        color: C.secondary,
        align: "center",
      }));
      return;
    }

    for (let i = 0; i < count; i += 1) {
      const card = makeCard(16);
      card.addChild(makeBadge(`אות / פסוק ${i + 1}`, C.secondary, C.gray5));

      if (currentLanguageMode === 0 || currentLanguageMode === 2) {
        const heText = cleanHtml(hebrewVerses[i] || "");
        if (heText) {
          const he = makeLabel(heText, {
            fontSize: currentFontSize,
            align: "right",
            marginTop: 10,
          });
          he.lineHeight = currentFontSize * 1.45;
          card.addChild(he);
        }
      }

      if (currentLanguageMode === 1 || currentLanguageMode === 2) {
        const enText = cleanHtml(englishVerses[i] || "");
        if (enText) {
          const en = makeLabel(enText, {
            fontSize: Math.max(12, currentFontSize - 3),
            color: currentLanguageMode === 2 ? C.secondary : C.label,
            align: "left",
            marginTop: 8,
          });
          en.lineHeight = Math.max(12, currentFontSize - 3) * 1.4;
          card.addChild(en);
        }
      }

      verses.addChild(card);
    }

    if (textData.prev || textData.next) {
      const navCard = makeCard(12);
      const row = new StackLayout();
      row.orientation = "horizontal";

      if (textData.prev) {
        const prev = makeButton(`← פרק קודם\n${textData.prev}`, () => {
          frame.navigate({
            create: () => createReaderPage(frame, textData.prev),
            animated: true,
          });
        }, { background: C.gray5, color: C.label, fontSize: 12, height: 50 });
        prev.width = textData.next ? "49%" : "100%";
        prev.marginRight = textData.next ? 6 : 0;
        row.addChild(prev);
      }

      if (textData.next) {
        const next = makeButton(`פרק הבא →\n${textData.next}`, () => {
          frame.navigate({
            create: () => createReaderPage(frame, textData.next),
            animated: true,
          });
        }, { background: C.blue, color: C.white, fontSize: 12, height: 50 });
        next.width = textData.prev ? "49%" : "100%";
        row.addChild(next);
      }

      navCard.addChild(row);
      verses.addChild(navCard);
    }
  }

  SefariaService.getText(refString)
    .then((data) => {
      spinner.busy = false;
      textData = data || {};
      if (data?.heRef) page.actionBar.title = data.heRef;
      renderVerses();
    })
    .catch((error) => {
      spinner.busy = false;
      verses.addChild(makeLabel(`שגיאה בטעינת הטקסט: ${error.message || error}`, {
        color: C.red,
        align: "center",
      }));
    });

  return page;
}

function openTextReader(frame, refString, customTitle) {
  if (!refString) return;
  frame.navigate({
    create: () => createReaderPage(frame, refString, customTitle),
    animated: true,
  });
}

// ----------------------------------------------------------------------------
// 4. Tab 1 — Daily Study / Calendars
// ----------------------------------------------------------------------------

function createCalendarsPage(frame) {
  const { page, content } = makeScrollPage("לימוד יומי");

  const header = makeSectionTitle(
    "לוח לימוד יומי - ספריא",
    "סדר הלימוד של היום: פרשת השבוע, דף יומי, 929, משנה ורמב\"ם",
    C.blue,
  );
  content.addChild(header);

  const itemsContainer = new StackLayout();
  content.addChild(itemsContainer);

  const spinner = makeSpinner();
  spinner.busy = true;
  content.addChild(spinner);

  SefariaService.getCalendars()
    .then((res) => {
      spinner.busy = false;
      const items = res?.calendar_items || [];

      if (res?.date) {
        const subtitle = header.getChildAt(1);
        if (subtitle) subtitle.text = `תאריך: ${res.date} | לוח הלימוד המעודכן ביותר`;
      }

      if (!items.length) {
        itemsContainer.addChild(makeLabel("לא נמצאו פריטי לימוד יומי.", {
          color: C.secondary,
          align: "center",
        }));
        return;
      }

      for (const item of items) {
        const card = makeCard(16);

        const badges = new WrapLayout();
        badges.orientation = "horizontal";
        const heCategory = item.title?.he || item.category || "לימוד יומי";
        badges.addChild(makeBadge(heCategory, C.blue, C.blueSoft));
        if (item.order != null) {
          const order = makeBadge(`#${item.order}`, C.secondary, C.gray5);
          order.marginLeft = 6;
          badges.addChild(order);
        }
        card.addChild(badges);

        card.addChild(makeLabel(
          item.displayValue?.he || item.ref || item.title?.en || "סעיף לימוד",
          { fontSize: 19, bold: true, align: "right", marginTop: 9 },
        ));

        if (item.displayValue?.en || item.ref) {
          card.addChild(makeLabel(item.displayValue?.en || item.ref, {
            fontSize: 13,
            color: C.secondary,
            marginTop: 3,
          }));
        }

        card.addChild(makeButton("פתח לקריאה ולימוד ←", () => {
          openTextReader(frame, item.ref, item.displayValue?.he || item.ref);
        }, { marginTop: 12 }));

        itemsContainer.addChild(card);
      }
    })
    .catch((error) => {
      spinner.busy = false;
      itemsContainer.addChild(makeLabel(`שגיאה בטעינת לוח השנה: ${error.message || error}`, {
        color: C.red,
        align: "center",
      }));
    });

  return page;
}

// ----------------------------------------------------------------------------
// 5. Tab 2 — Library
// ----------------------------------------------------------------------------

const LIBRARY_CATEGORIES = [
  {
    titleHe: "תנ\"ך",
    titleEn: "Tanakh",
    desc: "תורה, נביאים, כתובים עם מפרשים",
    sampleRefs: ["Genesis 1", "Exodus 1", "Psalms 23", "Isaiah 1"],
  },
  {
    titleHe: "משנה",
    titleEn: "Mishnah",
    desc: "ששה סדרי משנה (זרעים, מועד, נשים, נזיקין, קדשים, טהרות)",
    sampleRefs: ["Pirkei Avot 1", "Mishnah Berakhot 1", "Mishnah Shabbat 1"],
  },
  {
    titleHe: "תלמוד בבלי",
    titleEn: "Talmud Bavli",
    desc: "ש\"ס בבלי עם רש\"י ותוספות",
    sampleRefs: ["Berakhot 2a", "Shabbat 21b", "Bava Metzia 2a", "Sanhedrin 90a"],
  },
  {
    titleHe: "תלמוד ירושלמי",
    titleEn: "Talmud Yerushalmi",
    desc: "תלמוד ארץ ישראל",
    sampleRefs: ["Jerusalem Talmud Berakhot 1:1", "Jerusalem Talmud Peah 1:1"],
  },
  {
    titleHe: "מדרש",
    titleEn: "Midrash",
    desc: "מדרש רבה, תנחומא, פסיקתא, ילקוט שמעוני",
    sampleRefs: ["Bereshit Rabbah 1", "Midrash Tanchuma, Bereshit 1"],
  },
  {
    titleHe: "הלכה",
    titleEn: "Halakhah",
    desc: "משנה תורה להרמב\"ם, שולחן ערוך, משנה ברורה",
    sampleRefs: ["Mishneh Torah, Foundations of the Torah 1", "Shulchan Arukh, Orach Chayim 1"],
  },
  {
    titleHe: "קבלה וחסידות",
    titleEn: "Kabbalah & Chasidut",
    desc: "ספר הזוהר, ספר יצירה, תניא, ספרי חסידות",
    sampleRefs: ["Zohar 1:1a", "Tanya 1", "Sefer Yetzirah 1"],
  },
  {
    titleHe: "מחשבת ישראל ומוסר",
    titleEn: "Philosophy & Musar",
    desc: "מורה נבוכים, ספר הכוזרי, מסילת ישרים",
    sampleRefs: ["Mesillat Yesharim 1", "Guide for the Perplexed 1:1", "Kuzari 1"],
  },
];

function createLibraryPage(frame) {
  const { page, content } = makeScrollPage("ארון הספרים");

  for (const category of LIBRARY_CATEGORIES) {
    const card = makeCard(16);
    card.addChild(makeLabel(category.titleHe, {
      fontSize: 19,
      bold: true,
      align: "right",
    }));
    card.addChild(makeLabel(category.titleEn, {
      fontSize: 12,
      color: C.secondary,
      marginTop: 2,
    }));
    card.addChild(makeLabel(category.desc, {
      fontSize: 14,
      color: C.secondary,
      align: "right",
      marginTop: 8,
    }));

    const chips = new WrapLayout();
    chips.orientation = "horizontal";
    chips.marginTop = 10;
    for (const ref of category.sampleRefs) {
      chips.addChild(makeChip(ref, () => {
        openTextReader(frame, ref, `${category.titleHe}: ${ref}`);
      }));
    }
    card.addChild(chips);
    content.addChild(card);
  }

  return page;
}

// ----------------------------------------------------------------------------
// 6. Tab 3 — Search / reference autocomplete
// ----------------------------------------------------------------------------

function createSearchPage(frame) {
  const { page, content } = makeScrollPage("חיפוש מקורות");

  const searchCard = makeCard(16);
  searchCard.addChild(makeLabel("איתור מראה מקום או ספר", {
    fontSize: 17,
    bold: true,
    align: "right",
    marginBottom: 10,
  }));

  const field = new TextField();
  field.hint = "לדוגמה: בראשית א, Berakhot 2a, תהילים כג...";
  field.textAlignment = "right";
  field.fontSize = 16;
  field.height = 46;
  field.padding = "8 12";
  field.backgroundColor = C.gray6;
  field.borderRadius = 10;
  searchCard.addChild(field);

  const searchButton = makeButton("חפש ואתר מקור", () => performSearch(field.text), {
    marginTop: 10,
  });
  searchCard.addChild(searchButton);
  content.addChild(searchCard);

  const quickCard = makeCard(14);
  quickCard.addChild(makeLabel("מראי מקום נפוצים לגישה מהירה:", {
    fontSize: 13,
    color: C.secondary,
    marginBottom: 8,
  }));
  const chips = new WrapLayout();
  chips.orientation = "horizontal";
  const quickRefs = ["Genesis 1", "Exodus 20", "Psalms 23", "Berakhot 2a", "Pirkei Avot 1", "Tanya 1"];
  for (const ref of quickRefs) {
    chips.addChild(makeChip(ref, () => {
      field.text = ref;
      openTextReader(frame, ref);
    }));
  }
  quickCard.addChild(chips);
  content.addChild(quickCard);

  const results = new StackLayout();
  content.addChild(results);

  const spinner = makeSpinner();
  content.addChild(spinner);

  field.on("returnPress", () => performSearch(field.text));

  function performSearch(query) {
    const q = String(query || "").trim();
    if (!q) return;

    clearLayout(results);
    spinner.busy = true;

    SefariaService.searchName(q)
      .then((data) => {
        spinner.busy = false;
        const completions = data?.completion_objects || [];

        if (data?.is_ref && data?.ref) {
          const direct = makeCard(15);
          direct.backgroundColor = C.blueSoft;
          direct.addChild(makeBadge("התאמה ישירה של מראה מקום", C.white, C.blue));
          direct.addChild(makeLabel(data.ref, {
            fontSize: 18,
            bold: true,
            marginTop: 8,
          }));
          direct.addChild(makeButton("פתח מראה מקום זה עכשיו", () => {
            openTextReader(frame, data.ref);
          }, { marginTop: 10 }));
          results.addChild(direct);
        }

        if (!completions.length && !data?.is_ref) {
          const fallback = makeCard(15);
          fallback.addChild(makeLabel(`נסה לפתוח ישירות: "${q}"`, {
            fontSize: 16,
            bold: true,
            align: "right",
          }));
          fallback.addChild(makeButton("נסה לפתוח כטקסט", () => {
            openTextReader(frame, q);
          }, { marginTop: 10 }));
          results.addChild(fallback);
          return;
        }

        for (const completion of completions) {
          const card = makeCard(14);
          card.addChild(makeLabel(completion.title || completion.key || "תוצאה", {
            fontSize: 16,
            bold: true,
          }));
          card.addChild(makeLabel(`סוג: ${completion.type || "ספר/מקור"}`, {
            fontSize: 12,
            color: C.secondary,
            marginTop: 2,
          }));
          card.addChild(makeButton("פתח ←", () => {
            openTextReader(frame, completion.key || completion.title);
          }, {
            marginTop: 9,
            background: C.gray5,
            color: C.label,
            height: 36,
            fontSize: 13,
          }));
          results.addChild(card);
        }
      })
      .catch((error) => {
        spinner.busy = false;
        results.addChild(makeLabel(`שגיאה בחיפוש: ${error.message || error}`, {
          color: C.red,
        }));
      });
  }

  return page;
}

// ----------------------------------------------------------------------------
// 7. Tab 4 — Aramaic/Hebrew Lexicon
// ----------------------------------------------------------------------------

function createLexiconPage() {
  const { page, content } = makeScrollPage("מילון ארמי-עברי");

  content.addChild(makeSectionTitle(
    "מילון המונחים והשפה של ספריא",
    "חיפוש מילים בארמית של התלמוד, עברית מקראית ומילון יסטרוב (Jastrow).",
    C.indigo,
  ));

  const inputCard = makeCard(14);
  const field = new TextField();
  field.hint = "הזן מילה בארמית או בעברית (למשל: מאימתי, אתמר)...";
  field.textAlignment = "right";
  field.fontSize = 16;
  field.height = 46;
  field.padding = "8 12";
  field.backgroundColor = C.gray6;
  field.borderRadius = 10;
  inputCard.addChild(field);
  inputCard.addChild(makeButton("פרש מילה במילון", () => lookupWord(field.text), {
    background: C.indigo,
    marginTop: 10,
  }));
  content.addChild(inputCard);

  const sampleCard = makeCard(14);
  sampleCard.addChild(makeLabel("מילים נפוצות בתלמוד לבדיקה מהירה:", {
    fontSize: 13,
    color: C.secondary,
    marginBottom: 8,
  }));
  const words = ["מאימתי", "אתמר", "היכי", "גרסינן", "איכא", "שפיר"];
  const wordChips = new WrapLayout();
  wordChips.orientation = "horizontal";
  for (const word of words) {
    wordChips.addChild(makeChip(word, () => {
      field.text = word;
      lookupWord(word);
    }));
  }
  sampleCard.addChild(wordChips);
  content.addChild(sampleCard);

  const results = new StackLayout();
  content.addChild(results);

  const spinner = makeSpinner();
  content.addChild(spinner);

  field.on("returnPress", () => lookupWord(field.text));

  function lookupWord(word) {
    const value = String(word || "").trim();
    if (!value) return;

    clearLayout(results);
    spinner.busy = true;

    SefariaService.getLexicon(value)
      .then((entries) => {
        spinner.busy = false;

        if (!Array.isArray(entries) || !entries.length) {
          const noResult = makeCard(16);
          noResult.addChild(makeLabel(`לא נמצא ביאור מילוני עבור "${value}"`, {
            color: C.secondary,
            align: "center",
          }));
          results.addChild(noResult);
          return;
        }

        for (const entry of entries) {
          const card = makeCard(16);
          const lexiconName = entry.source || "מילון יסטרוב (Jastrow)";
          card.addChild(makeBadge(lexiconName, C.white, C.indigo));
          card.addChild(makeLabel(entry.headword || value, {
            fontSize: 20,
            bold: true,
            align: "right",
            marginTop: 8,
          }));

          if (entry.language_code || entry.morphology) {
            card.addChild(makeLabel(
              `שפה/דקדוק: ${entry.language_code || ""} ${entry.morphology || ""}`.trim(),
              { fontSize: 12, color: C.secondary, marginTop: 5 },
            ));
          }

          let definition = "";
          if (entry.content) {
            if (typeof entry.content === "string") {
              definition = cleanHtml(entry.content);
            } else if (Array.isArray(entry.content.senses)) {
              definition = entry.content.senses
                .map((sense) => cleanHtml(sense.definition || sense.grammar || ""))
                .filter(Boolean)
                .join("\n");
            }
          }

          if (definition) {
            card.addChild(makeLabel(definition, {
              fontSize: 15,
              align: "right",
              marginTop: 8,
            }));
          }
          results.addChild(card);
        }
      })
      .catch((error) => {
        spinner.busy = false;
        results.addChild(makeLabel(`שגיאה בשליפת המילון: ${error.message || error}`, {
          color: C.red,
        }));
      });
  }

  return page;
}

// ----------------------------------------------------------------------------
// 8. Root app — Core TabView + per-tab Core Frame navigation
// ----------------------------------------------------------------------------

function createTab(title, pageFactory) {
  const frame = new Frame();
  frame.navigate({
    create: () => pageFactory(frame),
    clearHistory: true,
    animated: false,
  });

  const item = new TabViewItem();
  item.title = title;
  item.view = frame;
  return item;
}

export function createSefariaCoreRoot() {
  const tabs = new TabView();
  tabs.selectedIndex = 0;
  tabs.items = [
    createTab("לימוד יומי", (frame) => createCalendarsPage(frame)),
    createTab("ארון הספרים", (frame) => createLibraryPage(frame)),
    createTab("חיפוש", (frame) => createSearchPage(frame)),
    createTab("מילון", () => createLexiconPage()),
  ];

  return tabs;
}

export function launchSefariaCoreApp() {
  console.log("[SefariaCoreMiniApp] Starting @nativescript/core version...");
  Application.run({
    create: () => createSefariaCoreRoot(),
  });
}

// Hanlin's NativeScript Core support hooks Application.run into the embedded
// NativeScript host. Launch immediately when the MiniApp bundle is evaluated.
launchSefariaCoreApp();
