type MapCoordinate = { latitude: number; longitude: number };
type MapRegion = {
  center: MapCoordinate;
  span: { latitudeDelta: number; longitudeDelta: number };
};

export const SNAPSHOT_DIRECTORY = `${FileManager.documentsDirectory}/Map Snapshots`;
export const DEFAULT_MAP_STYLE = {
  style: "imagery",
  elevation: "realistic",
} as const;

export type OrientationMode = "auto" | "portrait" | "landscape";
export type ResponseMode = "json" | "file" | "image" | "base64";

export type SnapshotRequest = {
  latitude?: number | string;
  longitude?: number | string;
  lat?: number | string;
  lon?: number | string;
  lng?: number | string;
  coordinates?: string;
  zoom?: number | string;
  distanceMeters?: number | string;
  latitudeDelta?: number | string;
  longitudeDelta?: number | string;
  width?: number | string;
  height?: number | string;
  w?: number | string;
  h?: number | string;
  orientation?: string;
  style?: string;
  elevation?: string;
  appearance?: string;
  scale?: number | string;
  showsTraffic?: boolean | string;
  pointsOfInterest?: string;
  saveToPhotos?: boolean | string;
  response?: string;
  returnBase64?: boolean | string;
  ui?: boolean | string;
  region?: MapRegion;
};

export type SnapshotMetadata = {
  ok: true;
  filePath: string;
  fileName: string;
  savedToPhotos: boolean;
  center: MapCoordinate;
  span: { latitudeDelta: number; longitudeDelta: number };
  size: { width: number; height: number };
  orientationRequested: OrientationMode;
  orientationUsed: "portrait" | "landscape" | "square";
  mapStyle: Record<string, unknown>;
  appearance?: "light" | "dark";
  scale?: number;
  zoom?: number;
  distanceMeters?: number;
  latitudeDelta: number;
  longitudeDelta: number;
  response: ResponseMode;
  base64?: string;
};

export type SnapshotExecution = {
  result: SnapshotMetadata;
  image: any;
  responseMode: ResponseMode;
};

function isObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function toNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const next = Number(value);
  return Number.isFinite(next) ? next : null;
}

function toBoolean(value: unknown): boolean | null {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  const text = String(value).trim().toLowerCase();
  if (["true", "1", "yes", "y", "on"].includes(text)) return true;
  if (["false", "0", "no", "n", "off"].includes(text)) return false;
  return null;
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function clampLatitude(latitude: number) {
  return clamp(latitude, -85, 85);
}

function wrapLongitude(longitude: number) {
  return ((((longitude + 180) % 360) + 360) % 360) - 180;
}

function normalizeOrientation(value: unknown): OrientationMode {
  const text = String(value ?? "auto").trim().toLowerCase();
  if (text === "portrait") return "portrait";
  if (text === "landscape") return "landscape";
  return "auto";
}

function normalizeResponseMode(value: unknown, returnBase64: unknown, fallback: ResponseMode): ResponseMode {
  const text = String(value ?? "").trim().toLowerCase();
  if (text === "json" || text === "file" || text === "image" || text === "base64") return text;
  if (toBoolean(returnBase64)) return "base64";
  return fallback;
}

function normalizeAppearance(value: unknown): "light" | "dark" | null {
  const text = String(value ?? "").trim().toLowerCase();
  if (text === "light" || text === "dark") return text;
  return null;
}

function currentScreenSize() {
  return {
    width: Math.max(1, Math.round(Number(Device.screen.width) || 1)),
    height: Math.max(1, Math.round(Number(Device.screen.height) || 1)),
  };
}

function baseSizeForOrientation(orientation: OrientationMode) {
  const screen = currentScreenSize();
  const shortSide = Math.min(screen.width, screen.height);
  const longSide = Math.max(screen.width, screen.height);

  if (orientation === "portrait") {
    return { width: shortSide, height: longSide };
  }
  if (orientation === "landscape") {
    return { width: longSide, height: shortSide };
  }
  return screen;
}

function resolveOutputSize(request: SnapshotRequest, orientation: OrientationMode) {
  const base = baseSizeForOrientation(orientation);
  const width = toNumber(request.width ?? request.w);
  const height = toNumber(request.height ?? request.h);
  const baseAspect = base.width / Math.max(1, base.height);

  if (width && height) {
    return {
      width: Math.max(1, Math.round(width)),
      height: Math.max(1, Math.round(height)),
    };
  }
  if (width) {
    return {
      width: Math.max(1, Math.round(width)),
      height: Math.max(1, Math.round(width / Math.max(0.1, baseAspect))),
    };
  }
  if (height) {
    return {
      width: Math.max(1, Math.round(height * Math.max(0.1, baseAspect))),
      height: Math.max(1, Math.round(height)),
    };
  }
  return base;
}

function normalizeRegion(region: MapRegion): MapRegion {
  return {
    center: {
      latitude: clampLatitude(Number(region.center.latitude)),
      longitude: wrapLongitude(Number(region.center.longitude)),
    },
    span: {
      latitudeDelta: clamp(Math.abs(Number(region.span.latitudeDelta)) || 0.01, 0.0001, 170),
      longitudeDelta: clamp(Math.abs(Number(region.span.longitudeDelta)) || 0.01, 0.0001, 360),
    },
  };
}

function regionFromCenterAndDistance(
  center: MapCoordinate,
  distanceMeters: number,
  aspectRatio: number,
): MapRegion {
  const safeDistance = Math.max(100, Number(distanceMeters) || 25_000);
  const safeAspect = Math.max(0.1, aspectRatio || 1);
  const latitudeDelta = Math.max(0.0005, safeDistance / 111_320);
  const longitudeDelta = Math.max(0.0005, latitudeDelta * safeAspect);

  return normalizeRegion({
    center,
    span: { latitudeDelta, longitudeDelta },
  });
}

function regionFromZoom(center: MapCoordinate, zoom: number, aspectRatio: number): MapRegion {
  const safeZoom = clamp(Number(zoom) || 15, 0, 22);
  const safeAspect = Math.max(0.1, aspectRatio || 1);
  const longitudeDelta = clamp(360 / Math.pow(2, safeZoom), 0.0001, 360);
  const latitudeDelta = clamp(longitudeDelta / safeAspect, 0.0001, 170);

  return normalizeRegion({
    center,
    span: { latitudeDelta, longitudeDelta },
  });
}

function orientationFromSize(size: { width: number; height: number }): "portrait" | "landscape" | "square" {
  if (size.width === size.height) return "square";
  return size.width > size.height ? "landscape" : "portrait";
}

function parseCoordinatesString(text: string): Record<string, unknown> {
  const cleaned = text.trim();
  const parts = cleaned.split(",").map((part) => part.trim());
  if (parts.length !== 2) return {};
  const latitude = toNumber(parts[0]);
  const longitude = toNumber(parts[1]);
  if (latitude === null || longitude === null) return {};
  return { latitude, longitude };
}

function parseQueryString(text: string): Record<string, string> {
  const query = text.includes("?") ? text.slice(text.indexOf("?") + 1) : text;
  return query
    .split("&")
    .filter(Boolean)
    .reduce((acc, entry) => {
      const [rawKey, ...rest] = entry.split("=");
      if (!rawKey) return acc;
      const key = decodeURIComponent(rawKey);
      const value = decodeURIComponent(rest.join("=") || "");
      acc[key] = value;
      return acc;
    }, {} as Record<string, string>);
}

export function parseSnapshotRequest(input: unknown): SnapshotRequest {
  if (!input) return {};
  if (isObject(input)) return input as SnapshotRequest;

  if (typeof input === "string") {
    const trimmed = input.trim();
    if (!trimmed) return {};

    if (trimmed.startsWith("{")) {
      try {
        const parsed = JSON.parse(trimmed);
        return isObject(parsed) ? (parsed as SnapshotRequest) : {};
      } catch (_) {
        return {};
      }
    }

    if (trimmed.includes("=") || trimmed.includes("&") || trimmed.startsWith("scripting://")) {
      return parseQueryString(trimmed) as SnapshotRequest;
    }

    if (trimmed.includes(",")) {
      return parseCoordinatesString(trimmed) as SnapshotRequest;
    }
  }

  return {};
}

export function hasAnyQueryParameters(raw: Record<string, unknown> | null | undefined) {
  return !!raw && Object.keys(raw).length > 0;
}

function resolveLatitude(request: SnapshotRequest): number | null {
  const direct = toNumber(request.latitude ?? request.lat);
  if (direct !== null) return clampLatitude(direct);

  if (typeof request.coordinates === "string") {
    const parsed = parseCoordinatesString(request.coordinates);
    const latitude = toNumber(parsed.latitude);
    if (latitude !== null) return clampLatitude(latitude);
  }

  return null;
}

function resolveLongitude(request: SnapshotRequest): number | null {
  const direct = toNumber(request.longitude ?? request.lng ?? request.lon);
  if (direct !== null) return wrapLongitude(direct);

  if (typeof request.coordinates === "string") {
    const parsed = parseCoordinatesString(request.coordinates);
    const longitude = toNumber(parsed.longitude);
    if (longitude !== null) return wrapLongitude(longitude);
  }

  return null;
}

async function resolveCenter(request: SnapshotRequest): Promise<MapCoordinate> {
  const latitude = resolveLatitude(request);
  const longitude = resolveLongitude(request);
  if (latitude !== null && longitude !== null) {
    return { latitude, longitude };
  }

  const currentLocation = await Location.requestCurrent();
  if (!currentLocation) {
    throw new Error("Unable to resolve a location. Pass latitude/longitude or allow location access.");
  }

  return {
    latitude: clampLatitude(Number(currentLocation.latitude)),
    longitude: wrapLongitude(Number(currentLocation.longitude)),
  };
}

function resolveRegion(center: MapCoordinate, size: { width: number; height: number }, request: SnapshotRequest) {
  if (request.region) {
    return normalizeRegion(request.region);
  }

  const latitudeDelta = toNumber(request.latitudeDelta);
  const longitudeDelta = toNumber(request.longitudeDelta);
  const aspectRatio = size.width / Math.max(1, size.height);

  if (latitudeDelta !== null || longitudeDelta !== null) {
    const latDelta = latitudeDelta ?? (longitudeDelta ?? 0.02) / Math.max(0.1, aspectRatio);
    const lngDelta = longitudeDelta ?? (latitudeDelta ?? 0.02) * Math.max(0.1, aspectRatio);
    return normalizeRegion({
      center,
      span: {
        latitudeDelta: latDelta,
        longitudeDelta: lngDelta,
      },
    });
  }

  const distanceMeters = toNumber(request.distanceMeters);
  if (distanceMeters !== null) {
    return regionFromCenterAndDistance(center, distanceMeters, aspectRatio);
  }

  const zoom = toNumber(request.zoom) ?? 15;
  return regionFromZoom(center, zoom, aspectRatio);
}

function buildMapStyle(request: SnapshotRequest) {
  const style = String(request.style ?? DEFAULT_MAP_STYLE.style).trim().toLowerCase();
  const elevation = String(request.elevation ?? DEFAULT_MAP_STYLE.elevation).trim().toLowerCase();
  const showsTraffic = toBoolean(request.showsTraffic);
  const pointsOfInterest = request.pointsOfInterest;

  const mapStyle: Record<string, unknown> = {
    style: style || DEFAULT_MAP_STYLE.style,
    elevation: elevation || DEFAULT_MAP_STYLE.elevation,
  };

  if (showsTraffic !== null) {
    mapStyle.showsTraffic = showsTraffic;
  }
  if (pointsOfInterest === "all" || pointsOfInterest === "excludingAll") {
    mapStyle.pointsOfInterest = pointsOfInterest;
  }

  return mapStyle;
}

function baseFileName(prefix = "map-snapshot") {
  return `${prefix}-${new Date().toISOString().replace(/[:.]/g, "-")}.png`;
}

async function executeSnapshot({
  region,
  size,
  mapStyle,
  appearance,
  scale,
  saveToPhotos,
  responseMode,
  requestedOrientation,
  zoom,
  distanceMeters,
}: {
  region: MapRegion;
  size: { width: number; height: number };
  mapStyle: Record<string, unknown>;
  appearance: "light" | "dark" | null;
  scale: number | null;
  saveToPhotos: boolean;
  responseMode: ResponseMode;
  requestedOrientation: OrientationMode;
  zoom: number | null;
  distanceMeters: number | null;
}): Promise<SnapshotExecution> {
  const options: any = {
    region,
    size,
    mapStyle,
  };
  if (appearance) options.appearance = appearance;
  if (scale && scale > 0) options.scale = scale;

  const snapshot = await MapSnapshotter.take(options);
  const pngData = snapshot.image.toPNGData();
  if (!pngData) {
    throw new Error("Failed to encode the map snapshot as PNG.");
  }

  const fileName = baseFileName();
  const filePath = `${SNAPSHOT_DIRECTORY}/${fileName}`;
  await FileManager.createDirectory(SNAPSHOT_DIRECTORY, true);
  await FileManager.writeAsData(filePath, pngData);

  let savedToPhotos = false;
  if (saveToPhotos) {
    try {
      savedToPhotos = await Photos.savePhoto(pngData, { fileName });
    } catch (_) {
      savedToPhotos = false;
    }
  }

  const result: SnapshotMetadata = {
    ok: true,
    filePath,
    fileName,
    savedToPhotos,
    center: region.center,
    span: region.span,
    size,
    orientationRequested: requestedOrientation,
    orientationUsed: orientationFromSize(size),
    mapStyle,
    latitudeDelta: region.span.latitudeDelta,
    longitudeDelta: region.span.longitudeDelta,
    response: responseMode,
  };

  if (appearance) result.appearance = appearance;
  if (scale && scale > 0) result.scale = scale;
  if (zoom !== null) result.zoom = zoom;
  if (distanceMeters !== null) result.distanceMeters = distanceMeters;

  if (responseMode === "base64") {
    result.base64 = snapshot.image.toPNGBase64String();
  }

  return {
    result,
    image: snapshot.image,
    responseMode,
  };
}

export async function createSnapshotFromRequest(
  requestLike: unknown,
  options?: { defaultResponse?: ResponseMode },
): Promise<SnapshotExecution> {
  const request = parseSnapshotRequest(requestLike);
  const orientation = normalizeOrientation(request.orientation);
  const size = resolveOutputSize(request, orientation);
  const center = await resolveCenter(request);
  const region = resolveRegion(center, size, request);
  const responseMode = normalizeResponseMode(
    request.response,
    request.returnBase64,
    options?.defaultResponse ?? "json",
  );
  const appearance = normalizeAppearance(request.appearance);
  const scale = toNumber(request.scale);
  const saveToPhotos = toBoolean(request.saveToPhotos) ?? false;
  const zoom = toNumber(request.zoom);
  const distanceMeters = toNumber(request.distanceMeters);

  return executeSnapshot({
    region,
    size,
    mapStyle: buildMapStyle(request),
    appearance,
    scale,
    saveToPhotos,
    responseMode,
    requestedOrientation: orientation,
    zoom,
    distanceMeters,
  });
}

export async function createSnapshotFromRegion(options: {
  region: MapRegion;
  size?: { width: number; height: number };
  mapStyle?: Record<string, unknown>;
  appearance?: "light" | "dark" | null;
  scale?: number | null;
  saveToPhotos?: boolean;
}): Promise<SnapshotExecution> {
  const size = options.size ?? currentScreenSize();
  return executeSnapshot({
    region: normalizeRegion(options.region),
    size,
    mapStyle: options.mapStyle ?? DEFAULT_MAP_STYLE,
    appearance: options.appearance ?? null,
    scale: options.scale ?? null,
    saveToPhotos: options.saveToPhotos ?? true,
    responseMode: "json",
    requestedOrientation: "auto",
    zoom: null,
    distanceMeters: null,
  });
}

export function requestedUI(requestLike: unknown, hasRawParameters: boolean) {
  const request = parseSnapshotRequest(requestLike);
  const ui = toBoolean(request.ui);
  if (ui === true) return true;
  if (ui === false) return false;
  return !hasRawParameters;
}
