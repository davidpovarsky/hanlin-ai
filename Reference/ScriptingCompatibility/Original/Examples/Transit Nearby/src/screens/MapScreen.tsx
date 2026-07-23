import {
  Annotation,
  Button,
  Grid,
  GridRow,
  GroupBox,
  Image,
  Label,
  Map,
  MapCompass,
  MapScaleView,
  MapUserLocationButton,
  Navigation,
  NavigationStack,
  Text,
  ZStack,
  useMemo,
  useObservable,
  useEffect,
  useState,
} from "scripting"
import { RouteBadge, distanceLabel } from "../components/TransitRows"
import { TransitTheme } from "../design/TransitTheme"
import type { StopBoard, TransitStop } from "../domain/models"
import { mapRegionForCoordinates } from "../utils/geo"
import { arrivalLabel } from "../utils/dates"
import { StopDetailsScreen } from "./StopDetailsScreen"
import { isFavorite, toggleFavorite } from "../storage/transitStorage"

export function MapScreen({
  stops,
  boards = {},
  navigationTitle = "מפה",
  onShowList,
}: {
  stops: TransitStop[]
  boards?: Record<string, StopBoard>
  navigationTitle?: string
  onShowList?: () => void
}) {
  const [selectedStop, setSelectedStop] = useState<TransitStop | null>(stops[0] ?? null)
  const [favorite, setFavorite] = useState(selectedStop ? isFavorite(selectedStop.code) : false)
  const camera = useObservable<MapCameraPosition>(useMemo(
    () => MapCameraPosition.region(mapRegionForCoordinates(stops.map(stop => stop.coordinate))),
    [stops.map(stop => stop.code).join(",")],
  ))

  useEffect(() => {
    if (selectedStop && !stops.some(stop => stop.code === selectedStop.code)) setSelectedStop(stops[0] ?? null)
  }, [stops.map(stop => stop.code).join(",")])

  useEffect(() => setFavorite(selectedStop ? isFavorite(selectedStop.code) : false), [selectedStop?.code])

  async function presentStop(stop: TransitStop) {
    await Navigation.present({
      element: <NavigationStack><StopDetailsScreen stop={stop} /></NavigationStack>,
      modalPresentationStyle: "pageSheet",
    })
  }

  const board = selectedStop ? boards[selectedStop.code] : undefined
  return (
    <ZStack
      alignment="bottom"
      navigationTitle={navigationTitle}
      navigationBarTitleDisplayMode="inline"
      environments={{ layoutDirection: "rightToLeft" }}
      toolbar={onShowList ? {
        topBarTrailing: <Button title="רשימת תחנות" systemImage="list.bullet" action={onShowList} />,
      } : undefined}
    >
      <Map
        cameraPosition={camera}
        mapStyle={{ style: "standard", showsTraffic: true, pointsOfInterest: { includes: ["publicTransport"] } }}
        controls={<><MapUserLocationButton /><MapCompass /><MapScaleView /></>}
      >
        {stops.slice(0, 30).map(stop => {
          const routeNumber = boards[stop.code]?.arrivals[0]?.routeNumber
          return (
            <Annotation key={stop.code} coordinate={stop.coordinate} title={stop.name} anchor="bottom" tag={stop.code}>
              <Button
                action={() => setSelectedStop(stop)}
                buttonStyle="borderedProminent"
                buttonBorderShape={{ roundedRectangleRadius: 7 }}
                controlSize="small"
              >
                {routeNumber
                  ? <Text fontWeight="bold" monospacedDigit>{routeNumber}</Text>
                  : <Image systemName="bus.fill" />}
              </Button>
            </Annotation>
          )
        })}
      </Map>
      {selectedStop ? (
        <GroupBox
          label={<Text font="title3" fontWeight="bold">{selectedStop.name}</Text>}
          padding={12}
          background={{ style: "regularMaterial", shape: { type: "rect", cornerRadius: 18 } }}
          shadow={{ color: "rgba(0,0,0,0.18)", radius: 10, y: 3 }}
        >
          <Grid alignment="trailing" horizontalSpacing={10} verticalSpacing={8}>
            <GridRow>
              <Image systemName="bus.stop.fill" foregroundStyle={TransitTheme.accent} />
              <Text foregroundStyle="secondaryLabel" frame={{ maxWidth: "infinity", alignment: "trailing" }}>
                {[distanceLabel(selectedStop.distanceMeters), selectedStop.address].filter(Boolean).join(" · ")}
              </Text>
              <Button title={favorite ? "הסר ממועדפים" : "מועדף"} systemImage={favorite ? "star.fill" : "star"} action={() => setFavorite(toggleFavorite(selectedStop))} buttonStyle="plain" />
            </GridRow>
            {board?.stale ? <GridRow><Label title="המידע אינו עדכני" systemImage="clock.arrow.circlepath" foregroundStyle={TransitTheme.warning} gridCellColumns={3} /></GridRow> : null}
            {board?.arrivals.slice(0, 3).map(arrival => (
              <GridRow key={arrival.id}>
                <RouteBadge number={arrival.routeNumber} />
                <Text lineLimit={1}>{arrival.headsign}</Text>
                <Text foregroundStyle={arrival.realtime ? TransitTheme.realtime : "secondaryLabel"}>
                  {arrivalLabel(arrival.expectedAt)}
                </Text>
              </GridRow>
            ))}
            <GridRow>
              <Button
                title="הצג את כל זמני ההגעה"
                systemImage="clock"
                action={() => void presentStop(selectedStop)}
                buttonStyle="borderedProminent"
                gridCellColumns={3}
                frame={{ maxWidth: "infinity" }}
              />
            </GridRow>
          </Grid>
        </GroupBox>
      ) : null}
    </ZStack>
  )
}
