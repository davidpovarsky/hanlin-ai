// model/i18n.ts — Localization system for Hebrew and English
// Supports automatic RTL/LTR direction based on language

import { Script, Widget, Device } from "scripting"

export type Language = "he" | "en"

// Direction mapping
export const DIRECTION: Record<Language, "rtl" | "ltr"> = {
  he: "rtl",
  en: "ltr",
}

// Storage key for language preference
const LANGUAGE_KEY = "nutrition_app_language"

// Default language detection based on system
function getSystemLanguage(): Language {
  const systemLang = Device.systemLanguageCode || "en"
  return systemLang === "he" ? "he" : "en"
}

// Get current language from storage or system
export function getCurrentLanguage(): Language {
  const stored = Storage.get<Language>(LANGUAGE_KEY)
  return stored || getSystemLanguage()
}

// Set language preference
export function setLanguage(lang: Language): void {
  Storage.set(LANGUAGE_KEY, lang)
  // Reload widget to reflect language change
  Widget.reloadAll()
}

// Translation strings
const TRANSLATIONS: Record<Language, Record<string, string>> = {
  he: {
    // App & Tabs
    appName: "אכילה חכמה",
    homeTab: "בית",
    historyTab: "היסטוריה",
    aiTab: "יועץ AI",
    settingsTab: "הגדרות",

    // Home Screen
    homeTitle: "תזונה יומית",
    streakDays: "ימים ברצף!",
    startNewStreak: "התחל סטריק חדש היום!",
    points: "נקודות",
    nextStation: "התחנה הבאה",
    inMinutes: "בעוד {{minutes}} דקות",
    now: "עכשיו!",
    allStations: "כל התחנות",
    markDone: "סיימתי",
    allDoneTitle: "כל הכבוד! סיימת את כל התחנות היום!",
    totalPoints: "סה\"כ {{points}} נקודות",

    // Stations
    breakfast: "ארוחת בוקר",
    morningSnack: "נשנוש בוקר",
    lunch: "ארוחת צהריים",
    afternoonSnack: "נשנוש אחה\"צ",
    dinner: "ארוחת ערב",

    // History Screen
    historyTitle: "היסטוריה",
    weeklyCompleted: "תחנות שהושלמו השבוע",
    weeklyPoints: "נקודות השבוע",
    statistics: "סטטיסטיקה",
    currentStreak: "סטריק נוכחי",
    days: "ימים",
    loggedDays: "ימים מתועדים",
    dailyAvgPoints: "ממוצע נקודות יומי",
    dayDetails: "פירוט ימים אחרונים",

    // AI Chat Screen
        aiTitle: "יועץ תזונה",
        quickActions: "פעולות מהירות",
        analyzeWeek: "נתח את השבוע שלי",
        giveEncouragement: "תן לי עידוד!",
        askSomething: "שאל משהו",
        exampleQuestion: "למשל: אכלתי פיצה בצהריים, מה כדאי לערב?",
        send: "שלח",
        thinking: "חושב...",
        answer: "תשובה",
        chatHistory: "היסטוריית שיחה",
            aiContext: "אתה יועץ תזונה אישי בעברית.",
            todayCompleted: "תחנות שהושלמו: ",
            todayPoints: "נקודות היום: ",
            streakLabel: "סטריק: ",
            weekHistory: "היסטוריה שבועית: ",
            todayStations: "תחנות שהושלמו היום: ",
            aiInstructions: "ענה בקצרה, באופן חם ואישי, עם עצות מעשיות.",
            analyzePrompt: "נתח את דפוסי האכילה שלי מהשבוע האחרון ותן לי 3 המלצות קונקרטיות לשבוע הבא.",
            historyLabel: "היסטוריה: ",
            currentStreakLabel: "סטריק נוכחי: ",
            todayLabel: "היום: ",
            aiSystemPrompt: "אתה יועץ תזונה מנוסה. דבר בעברית. ענה בקצרה עם ניתוח קונקרטי.",
            encouragementPrompt: "תן לי מסר עידוד אישי קצר וחם (2-3 משפטים) בהתבסס על הביצועים שלי.",
            todayCompletedShort: "היום השלמתי ",
            streakLabelShort: "הסטריק שלי: ",
            todayPointsShort: "הנקודות היום: ",
            encouragementSystemPrompt: "אתה מעודד אישי חם. כתוב בעברית, קצר וחם עם אמוג׳י.",
            aiError: "שגיאה בחיבור ל-AI. בדוק שמפתח ה-API מוגדר.",
            questionPrefix: "שאלה: ",
            answerPrefix: "תשובה: ",

    // Settings Screen
            settingsTitle: "הגדרות",
            notifications: "התראות",
            setupReminders: "הגדרת תזכורות (15 דק׳ לפני כל תחנה)",
            notificationsSet: "התראות הוגדרו בהצלחה!",
            notificationsError: "שגיאה בהגדרת התראות",
            clickToSetup: "לחץ להגדרת התראות",
            notificationsBody: "הגיע הזמן להתכונן ל{{station}}!",
            widget: "ווידג׳ט",
            refreshWidget: "רענון ווידג׳ט",
            widgetInstructions: "הוסף את הווידג׳ט של Scripting למסך הבית ובחר את הסקריפט הזה",
            data: "נתונים",
            resetData: "איפוס כל הנתונים",
            dataReset: "כל הנתונים נמחקו. הפעל מחדש.",
            info: "מידע",
            version: "גרסה",
            appDescription: "ווידג׳ט תזונה יומי — עוקב אחרי 5 תחנות אכילה ביום עם מערכת נקודות וסטריק.",
            aiDescription: "חיבור AI דרך DeepSeek להצעות אישיות וניתוח דפוסים.",

    // Language Selection
    language: "שפה",
    hebrew: "עברית",
    english: "English",

    // Common
        completed: "הושלם",
        of: "/",
        stations: "תחנות",
        pointsShort: "נק׳",
        today: "היום",
        week: "שבוע",
        month: "חודש",
        year: "שנה",
        ok: "אישור",
        cancel: "ביטול",
        save: "שמור",
        loading: "טוען...",
        error: "שגיאה",
        success: "הצלחה",
        // Station Detail
        details: "פרטים",
        recommendedTime: "שעה מומלצת",
        suggestionsTitle: "הצעות — מה לאכול?",
        whatDidYouEat: "מה אכלת?",
        noteOptional: "רשמי מה אכלת (אופציונלי)",
        markDoneWithPoints: "סיימתי! (+{{points}} נקודות)",
        status: "סטטוס",
        nowShort: "(עכשיו)",

    // AI Chat - Multi-thread
        chatNewConversation: "שיחה חדשה",
        chatHistoryTitle: "היסטוריית שיחות",
        chatBackToChat: "חזרה לשיחה",
        chatActions: "פעולות",
        chatNewChat: "שיחה חדשה",
        chatDeleteAll: "מחק הכל",
        chatDeleteAllConfirm: "למחוק את כל השיחות? לא ניתן לשחזר.",
        chatPreviousChats: "שיחות קודמות",
        chatMessages: "הודעות",
        chatNoHistory: "אין עדיין היסטוריית שיחות.\nהתחל שיחה חדשה!",
        chatConversation: "שיחה",
        chatYou: "אתה",
        chatAI: "יועץ",

        // AI Processing Toggle
                aiProcessing: "עיבוד נתונים על ידי AI",
                aiProcessingOn: "AI פעיל",
                aiProcessingOff: "AI מושבת",
                aiProcessingDescriptionOn: "AI מנתח את הנתונים שלך ומציע המלצות אישיות.",
                aiProcessingDescriptionOff: "AI מושבת. הנתונים לא ינוהלו על ידי AI.",
                // AI General Processing Toggle
                aiGeneralProcessing: "עיבוד כללי ב-AI",
                aiGeneralProcessingOn: "עיבוד כללי ב-AI פעיל",
                aiGeneralProcessingOff: "עיבוד כללי ב-AI מושבת",
                aiGeneralProcessingDescriptionOn: "כל יכולות ה-AI פעילות. ניתוח נתונים והצעות תפריטים מופעלים אוטומטית.",
                aiGeneralProcessingDescriptionOff: "עיבוד כללי ב-AI מושבת. ניתן להפעיל כל יכולת AI בנפרד.",
                // AI Meal Menu Creation Toggle
                aiMealMenuCreation: "יצירת וניתוח תפריטי האכילה להוספה להיסטוריה",
                aiMealMenuCreationOn: "יצירת תפריטים פעילה",
                aiMealMenuCreationOff: "יצירת תפריטים מושבתת",
                aiMealMenuCreationDescriptionOn: "AI יוצר תפריטים מומלצים ומנתח דפוסי אכילה להוספה להיסטוריה.",
                        aiMealMenuCreationDescriptionOff: "יצירת תפריטים מושבתת. AI לא ייצור תפריטים או יבצע ניתוחי היסטוריה.",
                        // Additional strings for UI
                        autoEnabledDueToGeneral: " (מופעל אוטומטית עקב עיבוד כללי)",


    // Home Screen — Enhanced
    skippedMeals: "ארוחות שדילגת",
    skippedWarning: "דילגת על ארוחה זו",
    mealDetail: "פרטי ארוחה",
    whatDidYouEatDetail: "מה אכלת בארוחה?",
    enterMealNote: "כתוב מה אכלת...",
    saveMeal: "שמור",
    completeAndSave: "סיימתי ושמור (+{{points}} נק׳)",
    editMeal: "עריכה",
    updateMeal: "עדכן",
    aiSuggestMeal: "הצע תפריט",
    aiSuggestTitle: "הצע לי תפריט",
    noNoteYet: "לא צוין מה אכלת",
    mealSaved: "נשמר!",
    timeWindow: "{{start}}–{{end}}",
    stationActive: "עכשיו!",
    stationUpcoming: "בעוד {{minutes}} דק׳",
    stationLate: "באיחור!",
    stationPassed: "עבר הזמן",
    todayProgress: "התקדמות היום",
    upcoming: "הארוחה הבאה",
    aiMenuPrompt: "הצע לי תפריט מומלץ ל{{meal}} ({{time}}). תן 3 אפשרויות עם פירוט קצר של מה לאכול.",
    aiMenuSystem: "אתה דיאטן מנוסה. הצע תפריט בריא ומעשי. כתוב בעברית, קצר וקולע.",
    continueInAiChat: "המשך שיחה עם היועץ",
  },
  en: {
    // App & Tabs
    appName: "Smart Eating",
    homeTab: "Home",
    historyTab: "History",
    aiTab: "AI Advisor",
    settingsTab: "Settings",

    // Home Screen
    homeTitle: "Daily Nutrition",
    streakDays: "day streak!",
    startNewStreak: "Start a new streak today!",
    points: "points",
    nextStation: "Next Station",
    inMinutes: "in {{minutes}} minutes",
    now: "Now!",
    allStations: "All Stations",
    markDone: "Mark Done",
    allDoneTitle: "Great job! You completed all stations today!",
    totalPoints: "Total {{points}} points",

    // Stations
    breakfast: "Breakfast",
    morningSnack: "Morning Snack",
    lunch: "Lunch",
    afternoonSnack: "Afternoon Snack",
    dinner: "Dinner",

    // History Screen
    historyTitle: "History",
    weeklyCompleted: "Stations Completed This Week",
    weeklyPoints: "Points This Week",
    statistics: "Statistics",
    currentStreak: "Current Streak",
    days: "days",
    loggedDays: "Days Logged",
    dailyAvgPoints: "Daily Points Average",
    dayDetails: "Recent Days Details",

    // AI Chat Screen
        aiTitle: "Nutrition Advisor",
        quickActions: "Quick Actions",
        analyzeWeek: "Analyze My Week",
        giveEncouragement: "Give Me Encouragement!",
        askSomething: "Ask Something",
        exampleQuestion: "e.g., I ate pizza for lunch, what should I have for dinner?",
        send: "Send",
        thinking: "Thinking...",
        answer: "Answer",
        chatHistory: "Chat History",
            aiContext: "You are a personal nutrition advisor in English.",
            todayCompleted: "Stations completed: ",
            todayPoints: "Today's points: ",
            streakLabel: "Streak: ",
            weekHistory: "Weekly history: ",
            todayStations: "Today's completed stations: ",
            aiInstructions: "Answer briefly, warmly and personally, with practical advice.",
            analyzePrompt: "Analyze my eating patterns from the last week and give me 3 concrete recommendations for next week.",
            historyLabel: "History: ",
            currentStreakLabel: "Current streak: ",
            todayLabel: "Today: ",
            aiSystemPrompt: "You are an experienced nutrition advisor. Speak in English. Answer briefly with concrete analysis.",
            encouragementPrompt: "Give me a short, warm personal encouragement message (2-3 sentences) based on my performance.",
            todayCompletedShort: "Today I completed ",
            streakLabelShort: "My streak: ",
            todayPointsShort: "Today's points: ",
            encouragementSystemPrompt: "You are a warm personal encourager. Write in English, short and warm with emojis.",
            aiError: "Error connecting to AI. Check that the API key is set.",
            questionPrefix: "Question: ",
            answerPrefix: "Answer: ",

    // Settings Screen
            settingsTitle: "Settings",
            notifications: "Notifications",
            setupReminders: "Setup Reminders (15 min before each station)",
            notificationsSet: "Notifications set successfully!",
            notificationsError: "Error setting up notifications",
            clickToSetup: "Click to setup notifications",
            notificationsBody: "Time to prepare for {{station}}!",
            widget: "Widget",
            refreshWidget: "Refresh Widget",
            widgetInstructions: "Add the Scripting widget to your home screen and select this script",
            data: "Data",
            resetData: "Reset All Data",
            dataReset: "All data cleared. Restart the app.",
            info: "Info",
            version: "Version",
            appDescription: "Daily nutrition widget — tracks 5 eating stations per day with a points system and streak.",
            aiDescription: "AI integration via DeepSeek for personalized suggestions and pattern analysis.",

    // Language Selection
    language: "Language",
    hebrew: "עברית",
    english: "English",

    // Common
        completed: "Completed",
        of: "/",
        stations: "stations",
        pointsShort: "pts",
        today: "Today",
        week: "Week",
        month: "Month",
        year: "Year",
        ok: "OK",
        cancel: "Cancel",
        save: "Save",
        loading: "Loading...",
        error: "Error",
        success: "Success",
        // Station Detail
        details: "Details",
        recommendedTime: "Recommended Time",
        suggestionsTitle: "Suggestions — What to eat?",
        whatDidYouEat: "What did you eat?",
        noteOptional: "Write what you ate (optional)",
        markDoneWithPoints: "Done! (+{{points}} points)",
        status: "Status",
        nowShort: "(now)",

    // AI Chat - Multi-thread
        chatNewConversation: "New Chat",
        chatHistoryTitle: "Chat History",
        chatBackToChat: "Back to Chat",
        chatActions: "Actions",
        chatNewChat: "New Chat",
        chatDeleteAll: "Delete All",
        chatDeleteAllConfirm: "Delete all conversations? This cannot be undone.",
        chatPreviousChats: "Previous Chats",
        chatMessages: "messages",
        chatNoHistory: "No chat history yet.\nStart a new conversation!",
        chatConversation: "Conversation",
        chatYou: "You",
        chatAI: "Advisor",

        // AI Processing Toggle
                aiProcessing: "AI Data Processing",
                aiProcessingOn: "AI Active",
                aiProcessingOff: "AI Disabled",
                aiProcessingDescriptionOn: "AI analyzes your data and provides personalized suggestions.",
                aiProcessingDescriptionOff: "AI disabled. Data will not be processed by AI.",
                // AI General Processing Toggle
                aiGeneralProcessing: "AI General Processing",
                aiGeneralProcessingOn: "AI General Processing Active",
                aiGeneralProcessingOff: "AI General Processing Disabled",
                aiGeneralProcessingDescriptionOn: "All AI capabilities active. Data analysis and menu suggestions are automatically enabled.",
                aiGeneralProcessingDescriptionOff: "AI general processing disabled. You can enable each AI capability separately.",
                // AI Meal Menu Creation Toggle
                aiMealMenuCreation: "Meal Menu Creation & Analysis for History",
                aiMealMenuCreationOn: "Meal Menu Creation Active",
                aiMealMenuCreationOff: "Meal Menu Creation Disabled",
                aiMealMenuCreationDescriptionOn: "AI creates recommended menus and analyzes eating patterns for history.",
                        aiMealMenuCreationDescriptionOff: "Meal menu creation disabled. AI will not create menus or perform history analysis.",
                        // Additional strings for UI
                        autoEnabledDueToGeneral: " (automatically enabled due to general processing)",


    // Home Screen — Enhanced
    skippedMeals: "Skipped Meals",
    skippedWarning: "You skipped this meal",
    mealDetail: "Meal Details",
    whatDidYouEatDetail: "What did you eat?",
    enterMealNote: "Write what you ate...",
    saveMeal: "Save",
    completeAndSave: "Done & Save (+{{points}} pts)",
    editMeal: "Edit",
    updateMeal: "Update",
    aiSuggestMeal: "Suggest Menu",
    aiSuggestTitle: "Suggest a Menu",
    noNoteYet: "No meal details noted",
    mealSaved: "Saved!",
    timeWindow: "{{start}}–{{end}}",
    stationActive: "Now!",
    stationUpcoming: "In {{minutes}} min",
    stationLate: "Late!",
    stationPassed: "Time passed",
    todayProgress: "Today's Progress",
    upcoming: "Next Meal",
    aiMenuPrompt: "Suggest a recommended menu for {{meal}} ({{time}}). Give 3 options with a brief description of what to eat.",
    aiMenuSystem: "You are an experienced dietitian. Suggest a healthy and practical menu. Write in English, short and to the point.",
    continueInAiChat: "Continue chat with advisor",
  },
}

// Helper to replace placeholders
function replacePlaceholders(text: string, values: Record<string, string | number>): string {
  let result = text
  for (const [key, value] of Object.entries(values)) {
    result = result.replace(new RegExp(`{{${key}}}`, "g"), String(value))
  }
  return result
}

// Main translation function
export function t(key: string, values?: Record<string, string | number>): string {
  const lang = getCurrentLanguage()
  const translation = TRANSLATIONS[lang][key] || TRANSLATIONS.en[key] || key
  
  if (values) {
    return replacePlaceholders(translation, values)
  }
  return translation
}

// Get current direction
export function getDirection(): "rtl" | "ltr" {
  return DIRECTION[getCurrentLanguage()]
}

// Format station name by ID
export function getStationName(stationId: number): string {
  const stationNames: Record<number, string> = {
    1: t("breakfast"),
    2: t("morningSnack"),
    3: t("lunch"),
    4: t("afternoonSnack"),
    5: t("dinner"),
  }
  return stationNames[stationId] || `Station ${stationId}`
}