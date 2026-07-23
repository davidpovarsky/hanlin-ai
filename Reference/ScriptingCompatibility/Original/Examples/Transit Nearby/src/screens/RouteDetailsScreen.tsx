import {
  Button,
  ContentUnavailableView,
  EnvironmentValuesReader,
  Grid,
  GridRow,
  HStack,
  Label,
  List,
  Map,
  MapCompass,
  MapPolyline,
  MapScaleView,
  Marker,
  ProgressView,
  Section,
  TabView,
  Text,
  useEffect,
  useObservable,
  useState,
} from "scripting"
import { loadRouteDetails } from "../data/transitRepository"
import type { RouteDetails, TransitRoute } from "../domain/models"
import { mapRegionForCoordinates } from "../utils/geo"
import { isFavoriteRoute, toggleFavoriteRoute } from "../storage/transitStorage"
import { AlertRow, RouteBadge } from "../components/TransitRows"
import { shortTime } from "../utils/dates"
import { routeColor } from "../design/TransitTheme"

export function RouteDetailsScreen({ route }: { route: TransitRoute }) {
  const [details, setDetails] = useState<RouteDetails | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [favorite, setFavorite] = useState(isFavoriteRoute(route.id))
  const selection = useObservable(0)
  const camera = useObservable<MapCameraPosition>(MapCameraPosition.automatic())

  async function refresh() {
    setErrorMessage(null)
    try {
      setDetails(await loadRouteDetails(route))
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : String(error))
    }
  }

  useEffect(() => {
    let cancelled = false
    loadRouteDetails(route)
      .then(value => {
        if (!cancelled) setDetails(value)
      })
      .catch(error => {
        if (!cancelled) setErrorMessage(error instanceof Error ? error.message : String(error))
      })
    return () => { cancelled = true }
  }, [route.id, route.number])

  useEffect(() => {
    if (!details) return
    const coordinates = details.polyline.length > 0
      ? details.polyline
      : details.stops.map(stop => stop.coordinate)
    camera.setValue(MapCameraPosition.region(mapRegionForCoordinates(coordinates)))
  }, [details?.patternId])

  if (!details && !errorMessage) {
    return <ProgressView title={`טוען את קו ${route.number}…`} navigationTitle={`קו ${route.number}`} />
  }

  if (!details) {
    return (
      <List navigationTitle={`קו ${route.number}`} listStyle="insetGroup" environments={{ layoutDirection: "rightToLeft" }}>
        <Section>
          <ContentUnavailableView title="פרטי הקו אינם זמינים" systemImage="bus" description={errorMessage ?? "נסה שוב מאוחר יותר"} />
          <Button title="נסה שוב" systemImage="arrow.clockwise" action={() => void refresh()} buttonStyle="borderedProminent" frame={{ maxWidth: "infinity" }} />
        </Section>
      </List>
    )
  }

  const map = (
    <Map
      cameraPosition={camera}
      mapStyle={{ style: "standard", showsTraffic: true }}
      controls={<><MapCompass /><MapScaleView /></>}
      tabItem={<Label title="מפה" systemImage="map.fill" />}
      tag={0}
      frame={{ maxWidth: "infinity", maxHeight: "infinity" }}
    >
      {details.polyline.length > 1 ? (
        <MapPolyline
          coordinates={details.polyline}
          strokeColor={details.route.color ?? "systemBlue"}
          strokeStyle={{ lineWidth: 5, lineCap: "round", lineJoin: "round" }}
        />
      ) : null}
      {details.stops.map((stop, index) => (
        <Marker
          key={`${stop.code}:${index}`}
          title={stop.name}
          coordinate={stop.coordinate}
          tint={details.route.color ?? "systemBlue"}
          monogram={String(index + 1)}
        />
      ))}
      {details.vehicles.map(vehicle => (
        <Marker
          key={vehicle.id}
          title={`קו ${details.route.number}`}
          coordinate={vehicle.coordinate}
          tint="systemBlue"
          systemImage="bus.fill"
        />
      ))}
    </Map>
  )

  const stops = (
    <List
      listStyle="insetGroup"
      tabItem={<Label title="תחנות" systemImage="list.number" />}
      tag={1}
      frame={{ maxWidth: "infinity", maxHeight: "infinity" }}
    >
      <Section title="פרטי הקו">
        <Grid alignment="trailing" horizontalSpacing={10} verticalSpacing={4} padding={{ vertical: 6 }}>
          <GridRow>
            <RouteBadge number={details.route.number} />
            <Text font="headline" frame={{ maxWidth: "infinity", alignment: "trailing" }}>{details.route.headsign || details.route.longName}</Text>
          </GridRow>
        </Grid>
        {details.route.operatorName ? <Text foregroundStyle="secondaryLabel">{details.route.operatorName}</Text> : null}
        {details.stale ? <Label title="המידע אינו עדכני" systemImage="clock.arrow.circlepath" foregroundStyle="systemOrange" /> : null}
      </Section>
      {details.alerts.length > 0 ? (
        <Section title="עדכוני שירות">{details.alerts.map(alert => <AlertRow key={alert.id} transitAlert={alert} />)}</Section>
      ) : null}
      <Section title={`${details.stops.length} תחנות`}>
        {details.stops.map((stop, index) => (
          <Grid key={`${stop.code}:${index}`} alignment="trailing" horizontalSpacing={10} verticalSpacing={2} padding={{ vertical: 4 }}>
            <GridRow>
              <Text font="caption" fontWeight="bold" foregroundStyle={routeColor(details.route)}>{index + 1}</Text>
              <Text font="body" fontWeight={index === 0 || index === details.stops.length - 1 ? "semibold" : "regular"} frame={{ maxWidth: "infinity", alignment: "trailing" }}>{stop.name}</Text>
            </GridRow>
            {stop.pickupAllowed === false || stop.dropoffAllowed === false ? (
              <GridRow><Text>{""}</Text><Text font="caption" foregroundStyle="secondaryLabel">{stop.pickupAllowed === false ? "הורדה בלבד" : "איסוף בלבד"}</Text></GridRow>
            ) : null}
          </Grid>
        ))}
      </Section>
      {details.scheduledTrips.length > 0 ? (
        <Section title="יציאות קרובות">
          {details.scheduledTrips.slice(0, 8).map(trip => <Label key={trip.id} title={`${shortTime(trip.departureAt)} · ${trip.headsign}`} systemImage="clock" />)}
        </Section>
      ) : null}
    </List>
  )

  const content = (
    <EnvironmentValuesReader keys={["horizontalSizeClass", "dynamicTypeSize"]}>
      {environment => {
        const sideBySide = environment.horizontalSizeClass === "regular"
          && !String(environment.dynamicTypeSize).startsWith("accessibility")
        return sideBySide ? <HStack spacing={0}>{stops}{map}</HStack> : (
          <TabView selection={selection}>{map}{stops}</TabView>
        )
      }}
    </EnvironmentValuesReader>
  )

  return (
    <HStack
      navigationTitle={`קו ${details.route.number}`}
      navigationBarTitleDisplayMode="inline"
      environments={{ layoutDirection: "rightToLeft" }}
      toolbar={{
        topBarLeading: <Button title="רענון" systemImage="arrow.clockwise" action={() => void refresh()} />,
        topBarTrailing: <Button title={favorite ? "הסר ממועדפים" : "הוסף למועדפים"} systemImage={favorite ? "star.fill" : "star"} action={() => setFavorite(toggleFavoriteRoute(details.route))} />,
      }}
    >
      {content}
    </HStack>
  )
}
