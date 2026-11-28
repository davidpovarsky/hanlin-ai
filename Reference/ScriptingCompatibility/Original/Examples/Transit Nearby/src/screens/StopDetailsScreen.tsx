import {
  Button,
  AppEvents,
  ContentUnavailableView,
  Grid,
  GridRow,
  Image,
  Label,
  List,
  NavigationLink,
  Navigation,
  NavigationStack,
  ProgressView,
  RoundedRectangle,
  Section,
  Text,
  useEffect,
  useState,
} from "scripting"
import { AlertRow, ArrivalCard, RealtimeLegend, RouteRow } from "../components/TransitRows"
import { loadStopBoard } from "../data/transitRepository"
import { TransitTheme } from "../design/TransitTheme"
import type { StopBoard, TransitArrival, TransitRoute, TransitStop } from "../domain/models"
import { startArrivalActivity, updateActiveArrivalActivity } from "../services/liveActivityService"
import { getCachedBoardState, getPreferences, isFavorite, toggleFavorite } from "../storage/transitStorage"
import { relativeUpdateLabel } from "../utils/dates"
import { RouteDetailsScreen } from "./RouteDetailsScreen"
import { MapScreen } from "./MapScreen"

export function StopDetailsScreen({ stop }: { stop: TransitStop }) {
  const cached = getCachedBoardState(stop.code)
  const [board, setBoard] = useState<StopBoard | null>(cached ? { ...cached.value, stale: cached.stale } : null)
  const [loading, setLoading] = useState(!cached)
  const [favorite, setFavorite] = useState(isFavorite(stop.code))
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [activityMessage, setActivityMessage] = useState<string | null>(null)
  const [, setClockTick] = useState(Date.now())

  async function refresh() {
    setErrorMessage(null)
    try {
      const next = await loadStopBoard(stop)
      setBoard(next)
      await updateActiveArrivalActivity(next)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    let cancelled = false
    let active = true
    let timer: ReturnType<typeof setTimeout> | null = null
    const interval = Math.max(20, getPreferences().refreshIntervalSeconds) * 1_000
    function schedule() {
      timer = setTimeout(() => {
        if (cancelled) return
        if (active) void refresh().finally(schedule)
        else schedule()
      }, interval)
    }
    const onPhase = (phase: "active" | "inactive" | "background") => {
      active = phase === "active"
      if (active && !cancelled) void refresh()
    }
    AppEvents.scenePhase.addListener(onPhase)
    void refresh().finally(schedule)
    return () => {
      cancelled = true
      if (timer) clearTimeout(timer)
      AppEvents.scenePhase.removeListener(onPhase)
    }
  }, [stop.code])

  useEffect(() => {
    let cancelled = false
    let timer: ReturnType<typeof setTimeout> | null = null
    const tick = () => {
      timer = setTimeout(() => {
        if (cancelled) return
        setClockTick(Date.now())
        tick()
      }, 15_000)
    }
    tick()
    return () => {
      cancelled = true
      if (timer) clearTimeout(timer)
    }
  }, [])

  async function showOnMap() {
    await Navigation.present({
      element: <NavigationStack><MapScreen stops={[stop]} boards={board ? { [stop.code]: board } : {}} navigationTitle={stop.name} /></NavigationStack>,
      modalPresentationStyle: "pageSheet",
    })
  }

  async function follow(arrival: TransitArrival) {
    const started = await startArrivalActivity(stop, arrival, board?.arrivals ?? [])
    setActivityMessage(started ? "המעקב החי הופעל" : "Live Activity אינה זמינה במכשיר")
  }

  function routeForArrival(arrival: TransitArrival): TransitRoute {
    return board?.routes.find(route => route.id === arrival.routeId) ?? {
      id: arrival.routeId,
      number: arrival.routeNumber,
      longName: "",
      headsign: arrival.headsign,
      operatorName: "",
      color: null,
    }
  }

  const overlay = loading && !board
    ? <ProgressView title="טוען זמני הגעה…" />
    : undefined

  return (
    <List
      navigationTitle="פרטי תחנה"
      navigationBarTitleDisplayMode="inline"
      listStyle="insetGroup"
      listRowSpacing={7}
      scrollContentBackground="hidden"
      background={TransitTheme.groupedBackground}
      overlay={overlay}
      environments={{ layoutDirection: "rightToLeft" }}
      refreshable={refresh}
      toolbar={{
        topBarLeading: <Button title="מפה" systemImage="map" action={() => void showOnMap()} />,
        topBarTrailing: <Button
          title={favorite ? "הסר ממועדפים" : "הוסף למועדפים"}
          systemImage={favorite ? "star.fill" : "star"}
          action={() => setFavorite(toggleFavorite(stop))}
        />,
      }}
    >
      <Section>
        <Grid alignment="trailing" horizontalSpacing={12} verticalSpacing={4} padding={{ vertical: 8 }}>
          <GridRow alignment="center">
            <Image
              systemName="bus.fill"
              foregroundStyle="white"
              padding={11}
              background={{ style: TransitTheme.accent, shape: { type: "rect", cornerRadius: 10 } }}
              frame={{ width: 48, height: 48 }}
            />
            <Grid alignment="trailing" verticalSpacing={3} frame={{ maxWidth: "infinity", alignment: "trailing" }}>
              <GridRow><Text font="title2" fontWeight="bold">{stop.name}</Text></GridRow>
              <GridRow><Text foregroundStyle="secondaryLabel">תחנה {stop.code}</Text></GridRow>
              {stop.address ? <GridRow><Text font="caption" foregroundStyle="secondaryLabel">{stop.address}</Text></GridRow> : null}
            </Grid>
          </GridRow>
        </Grid>
      </Section>

      {!board && errorMessage ? (
        <Section>
          <ContentUnavailableView
            title="זמני ההגעה אינם זמינים"
            systemImage="clock.badge.exclamationmark"
            description={errorMessage}
          />
          <Button title="נסה שוב" systemImage="arrow.clockwise" action={() => void refresh()} buttonStyle="borderedProminent" frame={{ maxWidth: "infinity" }} />
        </Section>
      ) : null}

      {board?.stale || board?.warningMessage ? (
        <Section>
          <Label
            title={board.stale ? "המידע אינו עדכני" : board.warningMessage ?? "מידע חלקי"}
            systemImage={board.stale ? "clock.arrow.circlepath" : "wifi.exclamationmark"}
            foregroundStyle="systemOrange"
          />
          <Button title="נסה לרענן" systemImage="arrow.clockwise" action={() => void refresh()} />
        </Section>
      ) : null}

      {board?.alerts.length ? (
        <Section title="עדכוני שירות">
          {board.alerts.map(alert => <AlertRow key={alert.id} transitAlert={alert} />)}
        </Section>
      ) : null}

      <Section
        header={<Text font="headline">הגעות בזמן אמת</Text>}
        footer={board ? <RealtimeLegend /> : undefined}
      >
        {board?.arrivals.length ? board.arrivals.slice(0, 8).map(arrival => {
          const route = routeForArrival(arrival)
          return (
            <NavigationLink
              key={arrival.id}
              destination={<RouteDetailsScreen route={route} />}
              listRowInsets={{ top: 2, bottom: 2, leading: 12, trailing: 12 }}
              listRowSeparator="hidden"
              listRowBackground={<RoundedRectangle cornerRadius={12} fill={TransitTheme.card} />}
            >
              <ArrivalCard arrival={arrival} route={route} />
            </NavigationLink>
          )
        }) : board ? <Text foregroundStyle="secondaryLabel">לא נמצאו נסיעות קרובות</Text> : null}
      </Section>

      {board?.arrivals[0] ? (
        <Section footer={activityMessage ? <Text foregroundStyle="secondaryLabel">{activityMessage}</Text> : undefined}>
          <Button
            title="מעקב חי"
            systemImage="dot.radiowaves.left.and.right"
            action={() => void follow(board.arrivals[0])}
            buttonStyle="borderedProminent"
            controlSize="large"
            frame={{ maxWidth: "infinity" }}
          />
        </Section>
      ) : null}

      <Section>
        {board ? <Label title={relativeUpdateLabel(board.updatedAt)} systemImage="arrow.clockwise" foregroundStyle="secondaryLabel" /> : null}
      </Section>

      {board?.routes.length ? (
        <Section title="קווים בתחנה">
          {board.routes.map(route => (
            <NavigationLink key={route.id} destination={<RouteDetailsScreen route={route} />}>
              <RouteRow route={route} />
            </NavigationLink>
          ))}
        </Section>
      ) : null}
    </List>
  )
}
