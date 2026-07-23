import {
  Button,
  ContentUnavailableView,
  DatePicker,
  Form,
  Label,
  List,
  NavigationLink,
  Picker,
  ProgressView,
  RoundedRectangle,
  Section,
  Slider,
  Text,
  TextField,
  Toggle,
  useEffect,
  useState,
} from "scripting"
import { RouteRow, StopCard } from "../components/TransitRows"
import { hasBusNearbyToken } from "../data/auth"
import { geocodePlaces, planJourney, searchRoutes, searchStops } from "../data/transitRepository"
import { TransitTheme } from "../design/TransitTheme"
import type { JourneyPlace, JourneyPlan, TransitRoute, TransitStop } from "../domain/models"
import { addRecentSearch, getFavorites, getPreferences, getRecentSearches } from "../storage/transitStorage"
import { JourneyDetailScreen, JourneyRow } from "./JourneyScreens"
import { RouteDetailsScreen } from "./RouteDetailsScreen"
import { SettingsScreen } from "./SettingsScreen"
import { StopDetailsScreen } from "./StopDetailsScreen"

type SearchMode = "stops" | "routes" | "journey"

export function SearchScreen() {
  const [mode, setMode] = useState<SearchMode>("stops")
  const [query, setQuery] = useState("")
  const [stops, setStops] = useState<TransitStop[]>([])
  const [routes, setRoutes] = useState<TransitRoute[]>([])
  const [loading, setLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    const trimmed = query.trim()
    const minimumLength = mode === "routes" ? 1 : 2
    if (mode === "journey" || trimmed.length < minimumLength) {
      setLoading(false)
      setStops([])
      setRoutes([])
      return () => { cancelled = true }
    }
    const timer = setTimeout(() => {
      setLoading(true)
      setErrorMessage(null)
      const request = mode === "stops" ? searchStops(trimmed) : searchRoutes(trimmed)
      request.then(result => {
        if (cancelled) return
        if (mode === "stops") setStops(result as TransitStop[])
        else setRoutes(result as TransitRoute[])
      }).catch(error => {
        if (!cancelled) setErrorMessage(error instanceof Error ? error.message : String(error))
      }).finally(() => {
        if (!cancelled) setLoading(false)
      })
    }, 350)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [query, mode])

  if (mode === "journey") {
    return <JourneyPlanner mode={mode} onModeChanged={setMode} />
  }

  const recent = getRecentSearches().filter(item => item.kind === (mode === "stops" ? "stop" : "route"))
  const favorites = getFavorites()
  return (
    <List
      navigationTitle="חיפוש"
      navigationBarTitleDisplayMode="large"
      listStyle="insetGroup"
      listRowSpacing={8}
      scrollContentBackground="hidden"
      background={TransitTheme.groupedBackground}
      environments={{ layoutDirection: "rightToLeft" }}
      searchable={{ value: query, onChanged: setQuery, prompt: mode === "stops" ? "שם תחנה, רחוב או קוד" : "מספר קו" }}
      overlay={loading ? <ProgressView title="מחפש…" /> : errorMessage && query.trim().length >= 2 ? (
        <ContentUnavailableView title="החיפוש נכשל" systemImage="wifi.exclamationmark" description={errorMessage} />
      ) : undefined}
    >
      <Section>{modePicker(mode, setMode)}</Section>
      {!query.trim() && mode === "stops" && favorites.length > 0 ? (
        <Section title="מועדפים">
          {favorites.slice(0, 4).map(stop => <TrackedStopLink key={stop.code} stop={stop} />)}
        </Section>
      ) : null}
      {!query.trim() && recent.length > 0 ? (
        <Section title="חיפושים אחרונים">
          {recent.slice(0, 6).map(item => (
            <Button key={`${item.kind}:${item.id}`} action={() => setQuery(item.kind === "route" ? item.title.replace(/^קו\s+/, "") : item.title)} buttonStyle="plain">
              <Label title={item.title} systemImage="clock.arrow.circlepath" />
            </Button>
          ))}
        </Section>
      ) : null}
      {query.trim().length < (mode === "routes" ? 1 : 2) ? (
        <Section>
          <ContentUnavailableView title="מה לחפש?" systemImage="magnifyingglass" description="הקלד לפחות שני תווים" />
        </Section>
      ) : mode === "stops" ? (
        <Section title="תחנות">
          {stops.map(stop => <TrackedStopLink key={stop.code} stop={stop} />)}
        </Section>
      ) : (
        <Section title="קווים">
          {routes.map(route => <TrackedRouteLink key={`${route.id}:${route.headsign}`} route={route} />)}
        </Section>
      )}
    </List>
  )
}

function modePicker(mode: SearchMode, onChanged: (mode: SearchMode) => void) {
  return (
    <Picker title="סוג חיפוש" value={mode} onChanged={(value: string) => onChanged(value as SearchMode)} pickerStyle="segmented">
      <Text tag="stops">תחנות</Text>
      <Text tag="routes">קווים</Text>
      <Text tag="journey">מסע</Text>
    </Picker>
  )
}

function TrackedStopLink({ stop }: { stop: TransitStop }) {
  return (
    <NavigationLink
      destination={<TrackedStopDestination stop={stop} />}
      listRowSeparator="hidden"
      listRowBackground={<RoundedRectangle cornerRadius={13} fill={TransitTheme.card} />}
    >
      <StopCard stop={stop} />
    </NavigationLink>
  )
}

function TrackedStopDestination({ stop }: { stop: TransitStop }) {
  useEffect(() => addRecentSearch({ id: stop.code, title: stop.name, subtitle: `תחנה ${stop.code}`, kind: "stop" }), [stop.code])
  return <StopDetailsScreen stop={stop} />
}

function TrackedRouteLink({ route }: { route: TransitRoute }) {
  return <NavigationLink destination={<TrackedRouteDestination route={route} />}><RouteRow route={route} /></NavigationLink>
}

function TrackedRouteDestination({ route }: { route: TransitRoute }) {
  useEffect(() => addRecentSearch({ id: route.id, title: `קו ${route.number}`, subtitle: route.headsign, kind: "route" }), [route.id])
  return <RouteDetailsScreen route={route} />
}

function JourneyPlanner({ mode, onModeChanged }: { mode: SearchMode; onModeChanged: (mode: SearchMode) => void }) {
  const preferences = getPreferences()
  const [fromText, setFromText] = useState("")
  const [toText, setToText] = useState("")
  const [date, setDate] = useState(Date.now())
  const [arriveBy, setArriveBy] = useState(false)
  const [wheelchair, setWheelchair] = useState(preferences.wheelchairDefault)
  const [maxWalkDistance, setMaxWalkDistance] = useState(1_000)
  const [fromOverride, setFromOverride] = useState<JourneyPlace | null>(null)
  const [results, setResults] = useState<JourneyPlan[]>([])
  const [loading, setLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  async function useCurrentLocation() {
    const location = await Location.requestCurrent({ forceRequest: false })
    if (!location) return
    const place: JourneyPlace = { name: "המיקום שלי", coordinate: { latitude: location.latitude, longitude: location.longitude } }
    setFromOverride(place)
    setFromText(place.name)
  }

  async function plan() {
    setLoading(true)
    setErrorMessage(null)
    try {
      const [from, to] = await Promise.all([fromOverride ? Promise.resolve(fromOverride) : resolvePlace(fromText), resolvePlace(toText)])
      if (!from || !to) throw new Error("לא נמצאו מוצא או יעד מתאימים")
      const plans = await planJourney({ from, to, date, arriveBy, wheelchair, maxWalkDistance })
      setResults(plans)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setLoading(false)
    }
  }

  if (!hasBusNearbyToken()) {
    return (
      <List navigationTitle="תכנון נסיעה" listStyle="insetGroup" environments={{ layoutDirection: "rightToLeft" }}>
        <Section>{modePicker(mode, onModeChanged)}</Section>
        <Section>
          <ContentUnavailableView
            title="נדרש חיבור ל־BusNearby"
            systemImage="lock.shield"
            description="תכנון מסע דורש כרגע אסימון מאומת. תחנות, הגעות חיות, קווים ולוחות זמנים ממשיכים לעבוד."
          />
          <NavigationLink destination={<SettingsScreen />}><Label title="פתח הגדרות אימות" systemImage="gearshape" /></NavigationLink>
        </Section>
      </List>
    )
  }

  return (
    <Form navigationTitle="תכנון נסיעה" formStyle="grouped" environments={{ layoutDirection: "rightToLeft" }}>
      <Section>{modePicker(mode, onModeChanged)}</Section>
      <Section title="מאיפה ולאן">
        <TextField title="מוצא" value={fromText} onChanged={value => { setFromOverride(null); setFromText(value) }} prompt="כתובת או מקום" />
        <Button title="המיקום שלי" systemImage="location.fill" action={() => void useCurrentLocation()} />
        <TextField title="יעד" value={toText} onChanged={setToText} prompt="כתובת או מקום" />
        <Button title="החלף" systemImage="arrow.up.arrow.down" action={() => { const value = fromText; setFromText(toText); setToText(value); setFromOverride(null) }} />
      </Section>
      <Section title="זמן והעדפות">
        <DatePicker title={arriveBy ? "הגעה עד" : "יציאה"} value={date} onChanged={setDate} startDate={Date.now() - 60_000} displayedComponents={["date", "hourAndMinute"]} />
        <Toggle title="הגעה עד השעה" systemImage="clock.arrow.circlepath" value={arriveBy} onChanged={setArriveBy} />
        <Toggle title="נגיש לכיסא גלגלים" systemImage="figure.roll" value={wheelchair} onChanged={setWheelchair} />
        <Text>מרחק הליכה מרבי: {Math.round(maxWalkDistance)} מטר</Text>
        <Slider value={maxWalkDistance} onChanged={setMaxWalkDistance} min={250} max={3_000} step={250} />
      </Section>
      <Section>
        <Button title="מצא מסלולים" systemImage="arrow.triangle.turn.up.right.diamond.fill" action={() => void plan()} buttonStyle="borderedProminent" controlSize="large" frame={{ maxWidth: "infinity" }} />
      </Section>
      {loading ? <Section><ProgressView title="מתכנן מסע…" /></Section> : null}
      {errorMessage ? <Section><Label title={errorMessage} systemImage="exclamationmark.triangle" foregroundStyle="systemOrange" /></Section> : null}
      {results.length > 0 ? (
        <Section title="אפשרויות">
          {results.map(result => <NavigationLink key={result.id} destination={<JourneyDetailScreen journey={result} />}><JourneyRow journey={result} /></NavigationLink>)}
        </Section>
      ) : null}
    </Form>
  )
}

async function resolvePlace(text: string): Promise<JourneyPlace | null> {
  const match = text.match(/^(.*)::(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/)
  if (match) return { name: match[1], coordinate: { latitude: Number(match[2]), longitude: Number(match[3]) } }
  return (await geocodePlaces(text))[0] ?? null
}
