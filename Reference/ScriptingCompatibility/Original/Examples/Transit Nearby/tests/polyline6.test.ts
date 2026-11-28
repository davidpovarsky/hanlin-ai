import { polyline6Fixture } from "../src/fixtures/polyline6Fixture"
import { decodePolyline6 } from "../src/utils/geo"

export function verifyPolyline6Fixture(): void {
  const actual = decodePolyline6(polyline6Fixture.encoded)
  if (actual.length !== polyline6Fixture.expected.length) {
    throw new Error(`Polyline fixture length mismatch: ${actual.length}`)
  }
  actual.forEach((coordinate, index) => {
    const expected = polyline6Fixture.expected[index]
    if (Math.abs(coordinate.latitude - expected.latitude) > 0.000001
      || Math.abs(coordinate.longitude - expected.longitude) > 0.000001) {
      throw new Error(`Polyline fixture mismatch at index ${index}`)
    }
  })
  if (decodePolyline6("\u0001invalid").length !== 0) {
    throw new Error("Malformed polyline should decode safely to an empty array")
  }
}

verifyPolyline6Fixture()
