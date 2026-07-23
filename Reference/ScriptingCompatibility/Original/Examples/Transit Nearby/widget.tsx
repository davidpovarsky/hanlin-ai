import {
  Button,
  ContentUnavailableView,
  Divider,
  Gauge,
  Grid,
  GridRow,
  HStack,
  Image,
  Spacer,
  Text,
  Widget,
} from "scripting"
import { CycleWidgetStationIntent, SelectWidgetStationIntent } from "./app_intents"
import { loadStopBoard } from "./src/data/transitRepository"
import { routeColorForNumber, TransitTheme } from "./src/design/TransitTheme"
import type { StopBoard, TransitArrival, TransitStop } from "./src/domain/models"
import { getCachedBoard, getFavorites, getRecentStops, getWidgetIndex } from "./src/storage/transitStorage"
import { arrivalLabel, relativeUpdateLabel } from "./src/utils/dates"

type WidgetConfiguration = {
  groupKey: string
  stopCodes?: string[]
}

function parseConfiguration(): WidgetConfiguration {
  if (!Widget.parameter) return { groupKey: "default" }
  try {
    const parsed = JSON.parse(Widget.parameter) as Partial<WidgetConfiguration>
    return {
      groupKey: typeof parsed.groupKey === "string" ? parsed.groupKey : Widget.parameter,
      stopCodes: Array.isArray(parsed.stopCodes)
        ? parsed.stopCodes.filter((value): value is string => typeof value === "string")
        : undefined,
    }
  } catch {
    return { groupKey: Widget.parameter }
  }
}

function allWidgetStops(configuration: WidgetConfiguration): TransitStop[] {
  const base = getFavorites().length > 0 ? getFavorites() : getRecentStops()
  if (!configuration.stopCodes?.length) return base
  const requested = new Set(configuration.stopCodes)
  return base.filter(stop => requested.has(stop.code))
}

function WidgetRouteBadge({ number }: { number: string }) {
  return (
    <Text
      font="headline"
      fontWeight="bold"
      monospacedDigit
      foregroundStyle="white"
      padding={{ horizontal: 6, vertical: 2 }}
      background={{ style: routeColorForNumber(number), shape: { type: "rect", cornerRadius: 5 } }}
    >{number}</Text>
  )
}

function ArrivalGridRow({ arrival, compact = false }: { arrival: TransitArrival; compact?: boolean }) {
  return (
    <GridRow alignment="center">
      <WidgetRouteBadge number={arrival.routeNumber} />
      {compact ? null : <Text font="caption" lineLimit={1} frame={{ maxWidth: "infinity", alignment: "trailing" }}>{arrival.headsign}</Text>}
      <Text
        font={compact ? "headline" : "caption"}
        fontWeight={arrival.realtime ? "semibold" : "regular"}
        foregroundStyle={arrival.realtime ? TransitTheme.realtime : "label"}
        monospacedDigit
        gridColumnAlignment="leading"
      >{arrivalLabel(arrival.expectedAt)}</Text>
      {arrival.realtime ? <Image systemName="dot.radiowaves.left.and.right" foregroundStyle={TransitTheme.realtime} imageScale="small" /> : null}
    </GridRow>
  )
}

function StationTabs({ stops, selectedIndex, groupKey }: {
  stops: TransitStop[]
  selectedIndex: number
  groupKey: string
}) {
  if (stops.length <= 1) return null
  return (
    <HStack spacing={3} gridCellColumns={4} frame={{ maxWidth: "infinity" }}>
      {stops.slice(0, 3).map((stop, index) => (
        <Button
          key={stop.code}
          title={stop.name}
          intent={SelectWidgetStationIntent({ index, groupKey })}
          buttonStyle={index === selectedIndex ? "borderedProminent" : "bordered"}
          controlSize="mini"
        />
      ))}
    </HStack>
  )
}

function StationControls({ groupKey, index, count }: { groupKey: string; index: number; count: number }) {
  if (count <= 1) return null
  return (
    <HStack gridCellColumns={4} frame={{ maxWidth: "infinity" }}>
      <Button
        title="התחנה הקודמת"
        systemImage="chevron.right"
        intent={CycleWidgetStationIntent({ direction: -1, groupKey })}
        buttonStyle="bordered"
      />
      <Spacer />
      <Text font="caption2" foregroundStyle="secondaryLabel">{index + 1} מתוך {count}</Text>
      <Spacer />
      <Button
        title="התחנה הבאה"
        systemImage="chevron.left"
        intent={CycleWidgetStationIntent({ direction: 1, groupKey })}
        buttonStyle="bordered"
      />
    </HStack>
  )
}

function StationPanel({ stop, board, compact = false }: { stop: TransitStop; board: StopBoard | null; compact?: boolean }) {
  const limit = compact ? 3 : 4
  return (
    <Grid
      alignment="trailing"
      horizontalSpacing={6}
      verticalSpacing={compact ? 4 : 6}
      padding={compact ? 0 : 8}
      background={compact ? undefined : { style: "quaternarySystemFill", shape: { type: "rect", cornerRadius: 12 } }}
    >
      <GridRow>
        <Image systemName="bus.stop.fill" foregroundStyle={TransitTheme.accent} />
        <Text font={compact ? "subheadline" : "headline"} fontWeight="bold" lineLimit={1} gridCellColumns={2}>{stop.name}</Text>
        <Text font="caption2" foregroundStyle="secondaryLabel">{stop.code}</Text>
      </GridRow>
      {board?.arrivals.slice(0, limit).map(arrival => <ArrivalGridRow key={arrival.id} arrival={arrival} compact={compact} />)}
      {!board?.arrivals.length ? (
        <GridRow><Text font="caption" foregroundStyle="secondaryLabel" gridCellColumns={4}>אין זמני הגעה זמינים</Text></GridRow>
      ) : null}
    </Grid>
  )
}

function SmallWidget({ stop, board, groupKey, index, count }: {
  stop: TransitStop
  board: StopBoard | null
  groupKey: string
  index: number
  count: number
}) {
  return (
    <Grid alignment="trailing" verticalSpacing={6} padding widgetBackground="systemBackground" environments={{ layoutDirection: "rightToLeft" }}>
      <GridRow><Text font="caption2" foregroundStyle="secondaryLabel" gridCellColumns={4}>התחנה הבאה</Text></GridRow>
      <GridRow><Text font="headline" fontWeight="bold" lineLimit={1} gridCellColumns={4}>{stop.name}</Text></GridRow>
      <GridRow><Text font="caption2" foregroundStyle="secondaryLabel" gridCellColumns={4}>{index + 1} מתוך {count}</Text></GridRow>
      <Divider gridCellColumns={4} />
      {board?.arrivals.slice(0, 3).map(arrival => <ArrivalGridRow key={arrival.id} arrival={arrival} compact />)}
      <StationControls groupKey={groupKey} index={index} count={count} />
    </Grid>
  )
}

function MediumWidget({ stop, board, stops, selectedIndex, groupKey }: {
  stop: TransitStop
  board: StopBoard | null
  stops: TransitStop[]
  selectedIndex: number
  groupKey: string
}) {
  return (
    <Grid alignment="trailing" horizontalSpacing={6} verticalSpacing={6} padding widgetBackground="systemBackground" environments={{ layoutDirection: "rightToLeft" }}>
      <StationTabs stops={stops} selectedIndex={selectedIndex} groupKey={groupKey} />
      <GridRow>
        <Text font="headline" fontWeight="bold" gridCellColumns={3}>{stop.name}</Text>
        <Image systemName={board?.hasRealtime ? "dot.radiowaves.left.and.right" : "clock"} foregroundStyle={TransitTheme.realtime} />
      </GridRow>
      <Divider gridCellColumns={4} />
      {board?.arrivals.slice(0, 4).map(arrival => <ArrivalGridRow key={arrival.id} arrival={arrival} />)}
      <StationControls groupKey={groupKey} index={selectedIndex} count={stops.length} />
    </Grid>
  )
}

function LargeWidget({ stops, boards, selectedIndex, groupKey }: {
  stops: TransitStop[]
  boards: Record<string, StopBoard | null>
  selectedIndex: number
  groupKey: string
}) {
  const first = stops[selectedIndex]
  const second = stops[(selectedIndex + 1) % stops.length]
  const alert = boards[first.code]?.alerts[0]
  return (
    <Grid alignment="trailing" horizontalSpacing={8} verticalSpacing={8} padding widgetBackground="systemBackground" environments={{ layoutDirection: "rightToLeft" }}>
      {alert ? (
        <GridRow background={{ style: "rgba(255,59,48,0.14)", shape: { type: "rect", cornerRadius: 11 } }} padding={8}>
          <Image systemName="exclamationmark.triangle.fill" foregroundStyle="systemRed" />
          <Text font="caption" lineLimit={2} gridCellColumns={3}>{alert.title}</Text>
        </GridRow>
      ) : null}
      <GridRow alignment="top">
        <StationPanel stop={first} board={boards[first.code]} />
        <StationPanel stop={second} board={boards[second.code]} />
      </GridRow>
      <GridRow>
        <Text font="caption2" foregroundStyle="secondaryLabel" gridCellColumns={3}>
          {boards[first.code] ? relativeUpdateLabel(boards[first.code]!.updatedAt) : "ממתין לעדכון"}
        </Text>
        <Image systemName="dot.radiowaves.left.and.right" foregroundStyle={TransitTheme.realtime} />
      </GridRow>
      <StationControls groupKey={groupKey} index={selectedIndex} count={stops.length} />
    </Grid>
  )
}

function AccessoryWidget({ stop, board }: { stop: TransitStop; board: StopBoard | null }) {
  const arrival = board?.arrivals[0]
  if (Widget.family === "accessoryCircular") {
    const minutes = arrival ? Math.max(0, Math.min(30, Math.round((arrival.expectedAt - Date.now()) / 60_000))) : 0
    return (
      <Gauge
        value={30 - minutes}
        min={0}
        max={30}
        label={<Image systemName="bus.fill" />}
        currentValueLabel={<Text font="headline" fontWeight="bold">{arrival?.routeNumber ?? "—"}</Text>}
        gaugeStyle="accessoryCircular"
        widgetAccentable
      />
    )
  }

  if (Widget.family === "accessoryInline") {
    return <Text>{arrival ? `${arrival.routeNumber} · ${arrivalLabel(arrival.expectedAt)} · ${stop.name}` : `${stop.name} · אין מידע`}</Text>
  }

  return (
    <Grid alignment="trailing" horizontalSpacing={8} verticalSpacing={2} widgetAccentable environments={{ layoutDirection: "rightToLeft" }}>
      <GridRow>
        <WidgetRouteBadge number={arrival?.routeNumber ?? "—"} />
        <Text font="headline" fontWeight="semibold">{arrival ? arrivalLabel(arrival.expectedAt) : "אין מידע"}</Text>
      </GridRow>
      <GridRow><Text font="caption" gridCellColumns={2} lineLimit={1}>{stop.name}</Text></GridRow>
    </Grid>
  )
}

function EmptyWidget() {
  return (
    <ContentUnavailableView
      title="אין תחנות"
      systemImage="star"
      description="הוסף תחנה למועדפים באפליקציה"
      widgetBackground="systemBackground"
    />
  )
}

async function run() {
  const configuration = parseConfiguration()
  const stops = allWidgetStops(configuration)
  if (stops.length === 0) {
    Widget.present(<EmptyWidget />, { reloadPolicy: { policy: "after", date: new Date(Date.now() + 15 * 60_000) } })
    return
  }

  const selectedIndex = getWidgetIndex(configuration.groupKey, stops.length)
  const selectedStop = stops[selectedIndex]
  const neededStops = Widget.family === "systemLarge"
    ? [selectedStop, stops[(selectedIndex + 1) % stops.length]]
    : [selectedStop]
  const boards: Record<string, StopBoard | null> = Object.fromEntries(neededStops.map(stop => [stop.code, getCachedBoard(stop.code)]))
  const loaded = await Promise.allSettled(neededStops.map(loadStopBoard))
  loaded.forEach(result => {
    if (result.status === "fulfilled") boards[result.value.stop.code] = result.value
  })

  const selectedBoard = boards[selectedStop.code]
  let content
  if (Widget.family.startsWith("accessory")) {
    content = <AccessoryWidget stop={selectedStop} board={selectedBoard} />
  } else if (Widget.family === "systemSmall") {
    content = <SmallWidget stop={selectedStop} board={selectedBoard} groupKey={configuration.groupKey} index={selectedIndex} count={stops.length} />
  } else if (Widget.family === "systemLarge") {
    content = <LargeWidget stops={stops} boards={boards} selectedIndex={selectedIndex} groupKey={configuration.groupKey} />
  } else {
    content = <MediumWidget stop={selectedStop} board={selectedBoard} stops={stops} selectedIndex={selectedIndex} groupKey={configuration.groupKey} />
  }

  Widget.present(content, {
    reloadPolicy: { policy: "after", date: new Date(Date.now() + 5 * 60_000) },
    relevance: { score: selectedBoard?.arrivals[0] ? 90 : 20, duration: 30 * 60 },
  })
}

void run()
