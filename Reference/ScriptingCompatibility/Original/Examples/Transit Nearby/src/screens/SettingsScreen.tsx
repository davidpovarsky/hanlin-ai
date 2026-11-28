import {
  Button,
  Form,
  Label,
  LabeledContent,
  Section,
  SecureField,
  Slider,
  Text,
  Toggle,
  Widget,
  useState,
} from "scripting"
import { getBusNearbyToken, removeBusNearbyToken, setBusNearbyToken } from "../data/auth"
import { endActiveArrivalActivity } from "../services/liveActivityService"
import {
  clearRecentSearches,
  clearTransitCache,
  getPreferences,
  resetFavorites,
  setPreferences,
  type TransitPreferences,
} from "../storage/transitStorage"

const REALTIME_KEY = "transit-nearby.settings.prefer-realtime"
const ALERTS_KEY = "transit-nearby.settings.show-alerts"

export function SettingsScreen() {
  const [preferRealtime, setPreferRealtime] = useState(Storage.get<boolean>(REALTIME_KEY) ?? true)
  const [showAlerts, setShowAlerts] = useState(Storage.get<boolean>(ALERTS_KEY) ?? true)
  const [preferences, setLocalPreferences] = useState<TransitPreferences>(getPreferences())
  const [tokenDraft, setTokenDraft] = useState("")
  const [authenticated, setAuthenticated] = useState(getBusNearbyToken() != null)
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [confirmCache, setConfirmCache] = useState(false)
  const [confirmRecents, setConfirmRecents] = useState(false)
  const [confirmFavorites, setConfirmFavorites] = useState(false)

  function updatePreferences(next: TransitPreferences) {
    setLocalPreferences(next)
    setPreferences(next)
  }

  function saveToken() {
    const saved = setBusNearbyToken(tokenDraft)
    setAuthenticated(saved || getBusNearbyToken() != null)
    setTokenDraft("")
    setStatusMessage(saved ? "האסימון נשמר ב־Keychain" : "לא הוזן אסימון תקין")
  }

  function removeToken() {
    removeBusNearbyToken()
    setAuthenticated(false)
    setTokenDraft("")
    setStatusMessage("האסימון הוסר")
  }

  return (
    <Form
      navigationTitle="הגדרות"
      navigationBarTitleDisplayMode="large"
      formStyle="grouped"
      environments={{ layoutDirection: "rightToLeft" }}
    >
      <Section title="מצב מקורות נתונים">
        <LabeledContent title="KavNav" value="ציבורי · זמן אמת ולוחות זמנים" />
        <LabeledContent title="BusNearby" value={authenticated ? "אסימון שמור" : "מצב ציבורי בלבד"} />
        <LabeledContent title="תוקף אסימון" value={authenticated ? "נבדק בקריאה הבאה" : "לא זמין"} />
        <Text font="footnote" foregroundStyle="secondaryLabel">
          בלי אסימון עדיין זמינים חיפוש תחנות, הגעות, קווים, התראות ורכבים דרך המקורות הציבוריים.
        </Text>
      </Section>

      <Section title="אימות BusNearby">
        <SecureField title="אסימון Bearer" value={tokenDraft} onChanged={setTokenDraft} prompt="הדבק אסימון ללא המילה Bearer" />
        <Button title="שמור באופן מאובטח" systemImage="key.fill" action={saveToken} disabled={!tokenDraft.trim()} />
        {authenticated ? <Button title="הסר אסימון" systemImage="trash" role="destructive" action={removeToken} /> : null}
        {statusMessage ? <Text font="footnote" foregroundStyle="secondaryLabel">{statusMessage}</Text> : null}
      </Section>

      <Section title="זמן אמת והתראות">
        <Toggle
          title="העדף זמני אמת"
          systemImage="dot.radiowaves.left.and.right"
          value={preferRealtime}
          onChanged={value => { setPreferRealtime(value); Storage.set(REALTIME_KEY, value) }}
        />
        <Toggle
          title="הצג התראות שירות"
          systemImage="exclamationmark.triangle"
          value={showAlerts}
          onChanged={value => { setShowAlerts(value); Storage.set(ALERTS_KEY, value) }}
        />
        <Text>רענון מסך תחנה: {preferences.refreshIntervalSeconds} שניות</Text>
        <Slider
          value={preferences.refreshIntervalSeconds}
          onChanged={value => updatePreferences({ ...preferences, refreshIntervalSeconds: Math.round(value) })}
          min={20}
          max={60}
          step={5}
        />
      </Section>

      <Section title="תחנות קרובות">
        <Text>רדיוס: {preferences.nearbyRadiusMeters} מטר</Text>
        <Slider
          value={preferences.nearbyRadiusMeters}
          onChanged={value => updatePreferences({ ...preferences, nearbyRadiusMeters: Math.round(value / 100) * 100 })}
          min={500}
          max={3_000}
          step={100}
        />
        <Text>מספר תחנות מרבי: {preferences.maximumNearbyStops}</Text>
        <Slider
          value={preferences.maximumNearbyStops}
          onChanged={value => updatePreferences({ ...preferences, maximumNearbyStops: Math.round(value) })}
          min={5}
          max={30}
          step={1}
        />
        <Toggle
          title="נגישות לכיסא גלגלים כברירת מחדל"
          systemImage="figure.roll"
          value={preferences.wheelchairDefault}
          onChanged={value => updatePreferences({ ...preferences, wheelchairDefault: value })}
        />
      </Section>

      <Section title="נתונים שמורים">
        <Button
          title="נקה מטמון"
          systemImage="externaldrive.badge.xmark"
          action={() => setConfirmCache(true)}
          confirmationDialog={{
            isPresented: confirmCache,
            onChanged: setConfirmCache,
            title: "לנקות את כל נתוני המטמון?",
            actions: <Button title="נקה מטמון" role="destructive" action={() => { clearTransitCache(); setStatusMessage("המטמון נוקה") }} />,
          }}
        />
        <Button
          title="נקה חיפושים אחרונים"
          systemImage="clock.badge.xmark"
          action={() => setConfirmRecents(true)}
          confirmationDialog={{
            isPresented: confirmRecents,
            onChanged: setConfirmRecents,
            title: "לנקות את החיפושים האחרונים?",
            actions: <Button title="נקה" role="destructive" action={() => clearRecentSearches()} />,
          }}
        />
        <Button
          title="אפס מועדפים"
          systemImage="star.slash"
          role="destructive"
          action={() => setConfirmFavorites(true)}
          confirmationDialog={{
            isPresented: confirmFavorites,
            onChanged: setConfirmFavorites,
            title: "להסיר את כל התחנות והקווים המועדפים?",
            actions: <Button title="אפס מועדפים" role="destructive" action={() => resetFavorites()} />,
          }}
        />
      </Section>

      <Section title="Widget ופעילות חיה">
        <Button title="רענן Widgets" systemImage="arrow.clockwise" action={() => Widget.reloadAll()} />
        <Button title="סיים מעקב חי" systemImage="stop.circle" action={() => void endActiveArrivalActivity()} />
      </Section>

      <Section title="פרטיות וייחוס">
        <Label title="המיקום משמש לאיתור תחנות בלבד" systemImage="location.fill" />
        <Text font="footnote" foregroundStyle="secondaryLabel">
          נתוני תחבורה: KavNav ו־BusNearby. מפה: Apple MapKit ומקורות המידע המוצגים בה. הפרויקט אינו קשור לבעלי השירותים ואינו שומר Cookies או מפתחות Mapbox.
        </Text>
      </Section>

      <Section title="אודות">
        <LabeledContent title="גרסה" value="2.1.0" />
        <LabeledContent title="ממשק" value="Scripting Native TSX" />
      </Section>
    </Form>
  )
}
