import type { Coordinate } from "../domain/models"
import type { MapRegion } from "scripting"

const EARTH_RADIUS_METERS = 6_371_000

function radians(value: number): number {
  return value * Math.PI / 180
}

export function distanceMeters(from: Coordinate, to: Coordinate): number {
  const dLatitude = radians(to.latitude - from.latitude)
  const dLongitude = radians(to.longitude - from.longitude)
  const fromLatitude = radians(from.latitude)
  const toLatitude = radians(to.latitude)
  const a = Math.sin(dLatitude / 2) ** 2
    + Math.cos(fromLatitude) * Math.cos(toLatitude) * Math.sin(dLongitude / 2) ** 2
  return EARTH_RADIUS_METERS * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

export function decodePolyline6(encoded: string): Coordinate[] {
  const coordinates: Coordinate[] = []
  let index = 0
  let latitude = 0
  let longitude = 0

  while (index < encoded.length) {
    const latitudeResult = decodeChunk(encoded, index)
    if (latitudeResult == null) break
    index = latitudeResult.nextIndex
    latitude += latitudeResult.delta

    const longitudeResult = decodeChunk(encoded, index)
    if (longitudeResult == null) break
    index = longitudeResult.nextIndex
    longitude += longitudeResult.delta

    coordinates.push({
      latitude: latitude / 1_000_000,
      longitude: longitude / 1_000_000,
    })
  }

  return coordinates
}

function decodeChunk(encoded: string, startIndex: number): { delta: number; nextIndex: number } | null {
  let index = startIndex
  let result = 0
  let shift = 0
  let byte = 0

  do {
    if (index >= encoded.length) return null
    byte = encoded.charCodeAt(index++) - 63
    if (byte < 0 || byte > 63 || shift > 30) return null
    result |= (byte & 0x1f) << shift
    shift += 5
  } while (byte >= 0x20)

  return {
    delta: (result & 1) !== 0 ? ~(result >> 1) : result >> 1,
    nextIndex: index,
  }
}

export function mapRegionForCoordinates(coordinates: Coordinate[]): MapRegion {
  if (coordinates.length === 0) {
    return {
      center: { latitude: 31.778, longitude: 35.235 },
      span: { latitudeDelta: 0.08, longitudeDelta: 0.08 },
    }
  }

  const latitudes = coordinates.map(item => item.latitude)
  const longitudes = coordinates.map(item => item.longitude)
  const minLatitude = Math.min(...latitudes)
  const maxLatitude = Math.max(...latitudes)
  const minLongitude = Math.min(...longitudes)
  const maxLongitude = Math.max(...longitudes)

  return {
    center: {
      latitude: (minLatitude + maxLatitude) / 2,
      longitude: (minLongitude + maxLongitude) / 2,
    },
    span: {
      latitudeDelta: Math.max(0.008, (maxLatitude - minLatitude) * 1.35),
      longitudeDelta: Math.max(0.008, (maxLongitude - minLongitude) * 1.35),
    },
  }
}
