import {
  Button,
  ContentUnavailableView,
  Label,
  List,
  NavigationLink,
  Picker,
  ProgressView,
  RoundedRectangle,
  Section,
  Text,
  useEffect,
  useState,
} from "scripting"
import { StopCard } from "../components/TransitRows"
import { findNearbyStops, loadStopBoard, searchStops } from "../data/transitRepository"
import { TransitTheme } from "../design/TransitTheme"
import type { Coordinate, StopBoard, TransitStop } from "../domain/models"
import { getCachedBoardState, getRecentStops } from "../storage/transitStorage"
import { MapScreen } from "./MapScreen"
import { StopDetailsScreen } from "./StopDetailsScreen"

type ViewMode = "list" | "map"
type BoardsByStop = Record<string, StopBoard>

function initialBoards(stops: TransitStop[]): BoardsByStop {
  const entries = stops.flatMap(stop => {
    const cached = getCachedBoardState(stop.code)
    return cached ? [[stop.code, { ...cached.value, stale: cached.stale }] as const] : []
  })
  return Object.fromEntries(entries)
}

export function NearbyScreen() {
  const initialStops = getRecentStops()
  const [stops, setStops] = useState<TransitStop[]>(initialStops)
  const [boards, setBoards] = useState<BoardsByStop>(initialBoards(initialStops))
  const [origin, setOrigin] = useState<Coordinate | null>(null)
  const [query, setQuery] = useState("")
  const [viewMode, setViewMode] = useState<ViewMode>("list")
  const [loading, setLoading] = useState(false)
  const [locationStarted, setLocationStarted] = useState(stops.length > 0)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  async function hydrateBoards(items: TransitStop[]) {
    const settled = await Promise.allSettled(items.slice(0, 8).map(loadStopBoard))
    const loaded = settled.flatMap(result => result.status === "fulfilled" ? [result.value] : [])
    if (loaded.length === 0) return
    setBoards(current => ({
      ...current,
      ...Object.fromEntries(loaded.map(board => [board.stop.code, board])),
    }))
  }

  async function loadNearby(forceRequest = false) {
    setLocationStarted(true)
    setLoading(true)
    setErrorMessage(null)
    try {
      await Location.setAccuracy("hundredMeters")
      const location = await Location.requestCurrent({ forceRequest })
      if (!location) throw new Error("לא התקבל מיקום מהמכשיר")
      const coordinate = { latitude: location.latitude, longitude: location.longitude }
      setOrigin(coordinate)
      const nearby = await findNearbyStops(coordinate)
      setStops(nearby)
      setBoards(initialBoards(nearby))
      if (nearby.length === 0) setErrorMessage("לא נמצאו תחנות קרובות")
      void hydrateBoards(nearby)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setLoading(false)
    }
  }

  async function choosePlace() {
    setLocationStarted(true)
    setLoading(true)
    setErrorMessage(null)
    try {
      const location = await Location.pickFromMap()
      if (!location) return
      const coordinate = { latitude: location.latitude, longitude: location.longitude }
      setOrigin(coordinate)
      const nearby = await findNearbyStops(coordinate)
      setStops(nearby)
      setBoards(initialBoards(nearby))
      void hydrateBoards(nearby)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (initialStops.length > 0) void loadNearby(false)
  }, [])

  useEffect(() => {
    let cancelled = false
    const timer = setTimeout(() => {
      if (query.trim().length < 2) return
      setLoading(true)
      searchStops(query, origin ?? undefined)
        .then(results => {
          if (cancelled) return
          setStops(results)
          setBoards(initialBoards(results))
          void hydrateBoards(results)
        })
        .catch(error => {
          if (!cancelled) setErrorMessage(error instanceof Error ? error.message : String(error))
        })
        .finally(() => {
          if (!cancelled) setLoading(false)
        })
    }, 400)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [query])

  const modePicker = (
    <Picker title="תצוגה" value={viewMode} onChanged={(value: string) => setViewMode(value as ViewMode)} pickerStyle="segmented">
      <Text tag="list">רשימה</Text>
      <Text tag="map">מפה</Text>
    </Picker>
  )

  if (viewMode === "map") {
    return (
      <MapScreen
        stops={stops}
        boards={boards}
        navigationTitle="תחבורה קרובה"
        onShowList={() => setViewMode("list")}
      />
    )
  }

  const overlay = loading && (locationStarted || query.trim().length >= 2) && stops.length === 0
    ? <ProgressView title="מאתר תחנות קרובות…" />
    : undefined

  return (
    <List
      navigationTitle="תחבורה קרובה"
      navigationBarTitleDisplayMode="inline"
      listStyle="insetGroup"
      listRowSpacing={8}
      listSectionSpacing="compact"
      scrollContentBackground="hidden"
      background={TransitTheme.groupedBackground}
      overlay={overlay}
      environments={{ layoutDirection: "rightToLeft" }}
      searchable={{ value: query, onChanged: setQuery, prompt: "חיפוש תחנה או מקום" }}
      refreshable={() => loadNearby(true)}
      toolbar={{
        topBarTrailing: <Button title="קרוב אליי" systemImage="location.fill" action={() => void loadNearby(true)} />,
      }}
    >
      <Section>
        <Text font="largeTitle" fontWeight="bold">תחנות קרובות</Text>
        {modePicker}
      </Section>
      {stops.length === 0 && !loading ? (
        <Section>
          <ContentUnavailableView
            title={errorMessage ? "לא ניתן להציג תחנות" : "מוצאים תחנות סביבך"}
            systemImage={errorMessage ? "location.slash" : "location.circle"}
            description={errorMessage ?? "המיקום משמש רק לחיפוש חד־פעמי של תחנות קרובות. אפשר גם לבחור מקום במפה או לחפש ידנית."}
          />
          <Button title={errorMessage ? "נסה שוב" : "השתמש במיקום שלי"} systemImage="location.fill" action={() => void loadNearby(true)} buttonStyle="borderedProminent" controlSize="large" frame={{ maxWidth: "infinity" }} />
          <Button title="בחר מקום במפה" systemImage="map" action={() => void choosePlace()} />
          <Text font="footnote" foregroundStyle="secondaryLabel">אפשר להשתמש בשדה החיפוש למעלה גם בלי הרשאת מיקום.</Text>
        </Section>
      ) : null}
      <Section title={query.trim() ? "תוצאות חיפוש" : "לפי המרחק ממך"}>
        {stops.map(stop => (
          <NavigationLink
            key={stop.code}
            destination={<StopDetailsScreen stop={stop} />}
            listRowInsets={{ top: 2, bottom: 2, leading: 12, trailing: 12 }}
            listRowSeparator="hidden"
            listRowBackground={<RoundedRectangle cornerRadius={13} fill={TransitTheme.card} />}
          >
            <StopCard stop={stop} board={boards[stop.code]} />
          </NavigationLink>
        ))}
      </Section>
      {errorMessage && stops.length > 0 ? (
        <Section footer={<Text foregroundStyle="secondaryLabel">{errorMessage}</Text>}>
          <Label title="חלק מהמידע אינו זמין כרגע" systemImage="wifi.exclamationmark" />
        </Section>
      ) : null}
    </List>
  )
}
