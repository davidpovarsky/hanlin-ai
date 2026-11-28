import {
  Button,
  DragGesture,
  Label,
  Map,
  MapScaleView,
  MagnifyGesture,
  Marker,
  ProgressView,
  useContext,
  useEffect,
  useObservable,
} from "scripting";
import { server } from "../class/server";
import type { Pin } from "../class/server";
import { MapSelectionContext } from "../context/MapSelection";
import { createSnapshotFromRegion, DEFAULT_MAP_STYLE } from "../lib/mapSnapshot";

type MapCoordinate = { latitude: number; longitude: number };
type MapRegion = {
  center: MapCoordinate;
  span: { latitudeDelta: number; longitudeDelta: number };
};

const DEFAULT_CENTER = { latitude: 31.2304, longitude: 121.4737 };
const DEFAULT_DISTANCE = 5_000_000;
const INITIAL_DISTANCE = 25_000;

function regionFromCenterAndDistance(
  center: MapCoordinate,
  distanceMeters: number,
): MapRegion {
  const safeDistance = Math.max(500, Number(distanceMeters) || INITIAL_DISTANCE);
  const aspectRatio = Math.max(0.1, Device.screen.width / Math.max(1, Device.screen.height));
  const latitudeDelta = Math.max(0.002, safeDistance / 111_320);
  const longitudeDelta = Math.max(0.002, latitudeDelta * aspectRatio);

  return {
    center,
    span: { latitudeDelta, longitudeDelta },
  };
}

function clampNumber(value: number, min: number, max: number) {
  const next = Number(value);
  if (!Number.isFinite(next)) return min;
  return Math.max(min, Math.min(max, next));
}

function clampLatitude(latitude: number) {
  return clampNumber(latitude, -85, 85);
}

function wrapLongitude(longitude: number) {
  const next = Number(longitude);
  if (!Number.isFinite(next)) return DEFAULT_CENTER.longitude;
  return ((((next + 180) % 360) + 360) % 360) - 180;
}

function normalizeRegion(region: MapRegion): MapRegion {
  const latitudeDelta = clampNumber(region.span.latitudeDelta, 0.0005, 170);
  const longitudeDelta = clampNumber(region.span.longitudeDelta, 0.0005, 360);

  return {
    center: {
      latitude: clampLatitude(region.center.latitude),
      longitude: wrapLongitude(region.center.longitude),
    },
    span: { latitudeDelta, longitudeDelta },
  };
}

function translationWidth(translation: any) {
  return Number(translation?.width ?? translation?.x ?? 0) || 0;
}

function translationHeight(translation: any) {
  return Number(translation?.height ?? translation?.y ?? 0) || 0;
}

function regionShiftedByDrag(region: MapRegion, dragDetails: any): MapRegion {
  const base = normalizeRegion(region);
  const width = Math.max(1, Number(Device.screen.width) || 1);
  const height = Math.max(1, Number(Device.screen.height) || 1);
  const dx = translationWidth(dragDetails?.translation);
  const dy = translationHeight(dragDetails?.translation);

  return normalizeRegion({
    center: {
      latitude: base.center.latitude + (dy / height) * base.span.latitudeDelta,
      longitude: base.center.longitude - (dx / width) * base.span.longitudeDelta,
    },
    span: base.span,
  });
}

function regionZoomed(region: MapRegion, factor: number): MapRegion {
  const base = normalizeRegion(region);
  const safeFactor = clampNumber(factor, 0.05, 20);

  return normalizeRegion({
    center: base.center,
    span: {
      latitudeDelta: base.span.latitudeDelta * safeFactor,
      longitudeDelta: base.span.longitudeDelta * safeFactor,
    },
  });
}

function regionFromMapCameraPosition(position: MapCameraPosition): MapRegion | null {
  if (position.region) return position.region;

  if (position.rect) {
    const center = position.rect.center;
    const widthMeters = Math.max(1, position.rect.size.width);
    const heightMeters = Math.max(1, position.rect.size.height);
    const metersPerDegreeLatitude = 111_320;
    const latitudeRadians = (center.latitude * Math.PI) / 180;
    const metersPerDegreeLongitude = Math.max(
      1,
      metersPerDegreeLatitude * Math.cos(latitudeRadians),
    );

    return {
      center,
      span: {
        latitudeDelta: heightMeters / metersPerDegreeLatitude,
        longitudeDelta: widthMeters / metersPerDegreeLongitude,
      },
    };
  }

  if (position.fallbackPosition) {
    return regionFromMapCameraPosition(position.fallbackPosition);
  }

  return null;
}

export function View(props: any) {
  const pins = useObservable<Pin[]>([]);
  const selection = useContext(MapSelectionContext);
  const showToast = useObservable(false);
  const toastMessage = useObservable("");
  const cameraPosition = useObservable<MapCameraPosition>(
    MapCameraPosition.region(regionFromCenterAndDistance(DEFAULT_CENTER, DEFAULT_DISTANCE)),
  );
  const lastUsableRegion = useObservable<MapRegion | null>(
    regionFromCenterAndDistance(DEFAULT_CENTER, DEFAULT_DISTANCE),
  );
  const activeMagnifyBaseRegion = useObservable<MapRegion | null>(null);

  async function init() {
    try {
      const currentLocation = await Location.requestCurrent();
      const nextRegion = regionFromCenterAndDistance(
        currentLocation ?? DEFAULT_CENTER,
        currentLocation ? INITIAL_DISTANCE : DEFAULT_DISTANCE,
      );
      lastUsableRegion.setValue(nextRegion);
      cameraPosition.setValue(MapCameraPosition.region(nextRegion));
    } catch (_) {
      const nextRegion = regionFromCenterAndDistance(DEFAULT_CENTER, DEFAULT_DISTANCE);
      lastUsableRegion.setValue(nextRegion);
      cameraPosition.setValue(MapCameraPosition.region(nextRegion));
    }

    const [p] = await Promise.all([
      server.getPins(),
      new Promise<void>((resolve) => setTimeout(() => resolve(), 20)),
    ]);
    pins.setValue(p);
  }

  useEffect(() => {
    init();
  }, []);

  useEffect(() => {
    const listener = (newValue: MapCameraPosition) => {
      const nextRegion = regionFromMapCameraPosition(newValue);
      if (nextRegion) {
        lastUsableRegion.setValue(nextRegion);
      }
    };

    cameraPosition.subscribe(listener);
    return () => cameraPosition.unsubscribe(listener);
  }, []);

  function currentTrackedRegion() {
    return (
      regionFromMapCameraPosition(cameraPosition.value) ??
      lastUsableRegion.value ??
      regionFromCenterAndDistance(DEFAULT_CENTER, DEFAULT_DISTANCE)
    );
  }

  function applyTrackedRegion(nextRegion: MapRegion) {
    const normalizedRegion = normalizeRegion(nextRegion);
    lastUsableRegion.setValue(normalizedRegion);
    cameraPosition.setValue(MapCameraPosition.region(normalizedRegion));
  }

  function trackRegionAfterDrag(details: any) {
    applyTrackedRegion(regionShiftedByDrag(currentTrackedRegion(), details));
  }

  function zoomTrackedRegion(factor: number) {
    applyTrackedRegion(regionZoomed(currentTrackedRegion(), factor));
  }

  function magnificationFromDetails(details: any) {
    const magnification = Number(details?.magnification ?? 1);
    if (!Number.isFinite(magnification) || magnification <= 0) return 1;
    return magnification;
  }

  function trackRegionDuringMagnify(details: any) {
    const baseRegion = activeMagnifyBaseRegion.value ?? currentTrackedRegion();
    if (!activeMagnifyBaseRegion.value) {
      activeMagnifyBaseRegion.setValue(baseRegion);
    }
    applyTrackedRegion(regionZoomed(baseRegion, 1 / magnificationFromDetails(details)));
  }

  function trackRegionAfterMagnify(details: any) {
    const baseRegion = activeMagnifyBaseRegion.value ?? currentTrackedRegion();
    applyTrackedRegion(regionZoomed(baseRegion, 1 / magnificationFromDetails(details)));
    activeMagnifyBaseRegion.setValue(null);
  }

  return (
    <Map
      {...props}
      cameraPosition={cameraPosition}
      selection={selection}
      mapStyle={DEFAULT_MAP_STYLE}
      simultaneousGesture={DragGesture({ minDistance: 1, coordinateSpace: "local" }).onEnded(trackRegionAfterDrag)}
      highPriorityGesture={MagnifyGesture(0.01)
        .onChanged(trackRegionDuringMagnify)
        .onEnded(trackRegionAfterMagnify)}
      controls={<MapScaleView />}
      toolbar={{
        topBarTrailing: [
          <ZoomMapButton title={"+"} systemImage={"plus.magnifyingglass"} action={() => zoomTrackedRegion(0.5)} />,
          <ZoomMapButton title={"-"} systemImage={"minus.magnifyingglass"} action={() => zoomTrackedRegion(2)} />,
          <CaptureMapButton
            currentRegion={currentTrackedRegion}
            showToast={showToast}
            toastMessage={toastMessage}
          />,
          <RefreshButton pins={pins} />,
        ],
      }}
      toast={{
        isPresented: showToast,
        message: toastMessage.value,
        duration: 2.5,
        position: "top",
      }}>
      {pins.value.map((pin) => (
        <Marker
          key={pin.id}
          tag={pin.id}
          title={pin.title}
          coordinate={pin.coordinate}
          tint={pin.tint}
        />
      ))}
    </Map>
  );
}

function CaptureMapButton({
  currentRegion,
  showToast,
  toastMessage,
}: {
  currentRegion: () => MapRegion;
  showToast: Observable<boolean>;
  toastMessage: Observable<string>;
}) {
  const isCapturing = useObservable(false);

  async function captureCurrentMap() {
    if (isCapturing.value) return;

    isCapturing.setValue(true);
    try {
      const execution = await createSnapshotFromRegion({
        region: currentRegion(),
        mapStyle: DEFAULT_MAP_STYLE,
        saveToPhotos: true,
      });

      toastMessage.setValue(
        execution.result.savedToPhotos
          ? `נשמר צילום מפה בתמונות: ${execution.result.fileName}`
          : `נשמר צילום מפה בקבצים: ${execution.result.fileName}`,
      );
      showToast.setValue(true);
      console.log("Map snapshot saved:", execution.result.filePath);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error("Failed to capture map snapshot:", message);
      toastMessage.setValue(`שגיאה בצילום המפה: ${message}`);
      showToast.setValue(true);
    } finally {
      isCapturing.setValue(false);
    }
  }

  return (
    <Button action={captureCurrentMap}>
      {isCapturing.value ? <ProgressView /> : <Label title={"צילום"} systemImage={"camera.viewfinder"} />}
    </Button>
  );
}

function ZoomMapButton({
  title,
  systemImage,
  action,
}: {
  title: string;
  systemImage: string;
  action: () => void;
}) {
  return (
    <Button action={action}>
      <Label title={title} systemImage={systemImage} />
    </Button>
  );
}

function RefreshButton({ pins }: { pins: Observable<Pin[]> }) {
  const isLoading = useObservable(false);
  return (
    <Button
      action={async () => {
        isLoading.setValue(true);
        const [p] = await Promise.all([
          server.getPins(),
          new Promise<void>((resolve) => setTimeout(() => resolve(), 20)),
        ]);
        pins.setValue(p);
        isLoading.setValue(false);
      }}>
      {isLoading.value ? <ProgressView /> : <Label title={"刷新"} systemImage={"arrow.clockwise"} />}
    </Button>
  );
}
