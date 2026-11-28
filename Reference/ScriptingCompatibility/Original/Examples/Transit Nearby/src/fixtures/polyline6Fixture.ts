import type { Coordinate } from "../domain/models"

// Five public route points retained from the captured BusNearby geometry and
// shortened at a complete coordinate boundary. No user location is included.
export const polyline6Fixture: { encoded: string; expected: Coordinate[] } = {
  encoded: "mfop}@wkjyaAzBm@jGwBhD_BpCeA",
  expected: [
    { latitude: 32.792695, longitude: 35.034828 },
    { latitude: 32.792633, longitude: 35.034851 },
    { latitude: 32.792499, longitude: 35.034911 },
    { latitude: 32.792414, longitude: 35.034959 },
    { latitude: 32.792341, longitude: 35.034994 },
  ],
}
