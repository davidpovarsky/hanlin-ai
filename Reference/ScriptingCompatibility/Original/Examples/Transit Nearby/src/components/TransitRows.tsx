import {
  DisclosureGroup,
  Grid,
  GridRow,
  HStack,
  Image,
  Label,
  Text,
  type Color,
} from "scripting"
import type { StopBoard, TransitAlert, TransitArrival, TransitRoute, TransitStop } from "../domain/models"
import { routeColor, routeColorForNumber, TransitTheme } from "../design/TransitTheme"
import { arrivalLabel, relativeUpdateLabel, shortTime } from "../utils/dates"

export function distanceLabel(distance: number | null): string {
  if (distance == null) return ""
  if (distance < 1_000) return `${Math.max(1, Math.round(distance))} מ׳`
  return `${(distance / 1_000).toFixed(1)} ק״מ`
}

function walkingLabel(stop: TransitStop): string {
  const seconds = stop.walkingDurationSeconds ?? (stop.distanceMeters == null ? null : stop.distanceMeters / 1.3)
  if (seconds == null) return ""
  return `${Math.max(1, Math.round(seconds / 60))} דק׳ הליכה`
}

function freshnessLabel(arrival: TransitArrival): string {
  if (!arrival.realtime) return "לפי לוח הזמנים"
  if (arrival.freshness === "live") return "מידע בזמן אמת"
  if (arrival.freshness === "delayed") return "דיווח מתעכב"
  return "מידע ישן"
}

function badgeBackground(color: Color) {
  return { style: color, shape: { type: "rect", cornerRadius: 6 } as const }
}

export function RouteBadge({ number, color }: { number: string; color?: Color }) {
  return (
    <Text
      font="headline"
      fontWeight="bold"
      monospacedDigit
      foregroundStyle="white"
      padding={{ horizontal: 7, vertical: 3 }}
      background={badgeBackground(color ?? routeColorForNumber(number))}
      accessibilityLabel={`קו ${number}`}
    >{number}</Text>
  )
}

function routeForArrival(board: StopBoard | null, arrival: TransitArrival): TransitRoute | undefined {
  return board?.routes.find(route => route.id === arrival.routeId || route.number === arrival.routeNumber)
}

export function StopCard({ stop, board }: { stop: TransitStop; board?: StopBoard | null }) {
  const routeBadges = (board?.routes.length ? board.routes : board?.arrivals.map(arrival => ({
    id: arrival.routeId,
    number: arrival.routeNumber,
    color: null,
    headsign: arrival.headsign,
    longName: "",
    operatorName: "",
  })) ?? []).filter((route, index, all) => all.findIndex(item => item.number === route.number) === index).slice(0, 3)
  const nextArrivals = board?.arrivals.slice(0, 3) ?? []

  return (
    <Grid
      alignment="trailing"
      horizontalSpacing={10}
      verticalSpacing={7}
      padding={{ vertical: 7 }}
      accessibilityLabel={`${stop.name}, תחנה ${stop.code}${stop.distanceMeters == null ? "" : `, ${distanceLabel(stop.distanceMeters)}`}`}
    >
      <GridRow alignment="center">
        <Image
          systemName="bus.fill"
          foregroundStyle="white"
          padding={9}
          background={badgeBackground(TransitTheme.accent)}
          frame={{ width: 40, height: 40 }}
        />
        <Grid alignment="trailing" verticalSpacing={2} frame={{ maxWidth: "infinity", alignment: "trailing" }}>
          <GridRow><Text font="headline" fontWeight="semibold" lineLimit={1}>{stop.name}</Text></GridRow>
          <GridRow>
            <Text font="caption" foregroundStyle="secondaryLabel" lineLimit={1}>
              {[distanceLabel(stop.distanceMeters), walkingLabel(stop), stop.code ? `תחנה ${stop.code}` : ""].filter(Boolean).join(" · ")}
            </Text>
          </GridRow>
        </Grid>
      </GridRow>
      {routeBadges.length > 0 ? (
        <GridRow>
          <Text gridColumnAlignment="leading">{""}</Text>
          <HStack spacing={6} gridColumnAlignment="trailing" gridCellColumns={2}>
            {routeBadges.map(route => <RouteBadge key={route.id} number={route.number} color={routeColor(route)} />)}
          </HStack>
        </GridRow>
      ) : null}
      <GridRow>
        <Text>{""}</Text>
        <Text
          font="caption"
          foregroundStyle={nextArrivals.some(arrival => arrival.realtime) ? TransitTheme.realtime : "secondaryLabel"}
          gridColumnAlignment="trailing"
          lineLimit={1}
        >
          {board?.stale ? "מידע שמור · " : ""}{nextArrivals.length
            ? nextArrivals.map(arrival => `${arrival.routeNumber} ${arrivalLabel(arrival.expectedAt)}`).join("  ·  ")
          : "טוען זמני הגעה…"}{board ? ` · ${relativeUpdateLabel(board.updatedAt)}` : ""}
        </Text>
      </GridRow>
    </Grid>
  )
}

export function StopRow({ stop }: { stop: TransitStop }) {
  return <StopCard stop={stop} />
}

export function ArrivalCard({ arrival, route }: { arrival: TransitArrival; route?: TransitRoute }) {
  return (
    <Grid
      alignment="trailing"
      horizontalSpacing={10}
      verticalSpacing={3}
      padding={{ vertical: 5 }}
      accessibilityLabel={`קו ${arrival.routeNumber}, ${arrival.headsign}, ${arrivalLabel(arrival.expectedAt)}, ${freshnessLabel(arrival)}`}
    >
      <GridRow alignment="center">
        <RouteBadge number={arrival.routeNumber} color={route ? routeColor(route) : undefined} />
        <Grid alignment="trailing" verticalSpacing={2} frame={{ maxWidth: "infinity", alignment: "trailing" }}>
          <GridRow><Text font="headline" fontWeight="semibold" lineLimit={1}>{arrival.headsign || `קו ${arrival.routeNumber}`}</Text></GridRow>
          <GridRow>
            <Text font="caption" foregroundStyle="secondaryLabel">
              {route?.longName || (arrival.realtime ? "זמן אמת" : "לפי לוח הזמנים")}
            </Text>
          </GridRow>
        </Grid>
        <Grid alignment="leading" verticalSpacing={2}>
          <GridRow>
            <Text
              font="headline"
              fontWeight={arrival.realtime ? "semibold" : "regular"}
              foregroundStyle={arrival.freshness === "live" ? TransitTheme.realtime : arrival.freshness === "stale" || arrival.freshness === "delayed" ? TransitTheme.warning : "label"}
              monospacedDigit
            >{arrivalLabel(arrival.expectedAt)}</Text>
          </GridRow>
          <GridRow><Text font="caption2" foregroundStyle="secondaryLabel">{freshnessLabel(arrival)} · {shortTime(arrival.expectedAt)}</Text></GridRow>
        </Grid>
      </GridRow>
    </Grid>
  )
}

export function ArrivalRow({ arrival }: { arrival: TransitArrival }) {
  return <ArrivalCard arrival={arrival} />
}

export function RouteRow({ route }: { route: TransitRoute }) {
  return (
    <Grid alignment="trailing" horizontalSpacing={10} padding={{ vertical: 4 }}>
      <GridRow alignment="center">
        <RouteBadge number={route.number} color={routeColor(route)} />
        <Text font="headline" lineLimit={1} frame={{ maxWidth: "infinity", alignment: "trailing" }}>
          {route.headsign || route.longName}
        </Text>
      </GridRow>
    </Grid>
  )
}

export function AlertRow({ transitAlert }: { transitAlert: TransitAlert }) {
  return (
    <DisclosureGroup label={<Label title={transitAlert.title} systemImage="exclamationmark.triangle.fill" />}>
      <Text foregroundStyle="secondaryLabel">{transitAlert.description || "אין פרטים נוספים"}</Text>
    </DisclosureGroup>
  )
}

export function RealtimeLegend() {
  return (
    <Label
      title="זמן הגעה משוער בזמן אמת"
      systemImage="dot.radiowaves.left.and.right"
      font="caption"
      foregroundStyle={TransitTheme.realtime}
    />
  )
}
