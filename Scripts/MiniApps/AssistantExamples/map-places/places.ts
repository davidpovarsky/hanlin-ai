import type { HanlinAssistantToolHandler } from '@hanlin/assistant-tools';

interface Arguments { query: string }
interface Configuration {
  area: { latitude: number; longitude: number; radiusMeters: number };
  categories: string[];
}
const fixtures = [
  { id: 'demo-cafe', name: 'Demo café', category: 'restaurant', latitude: 31.7784, longitude: 35.2339 },
  { id: 'demo-museum', name: 'Demo museum', category: 'museum', latitude: 31.7790, longitude: 35.2350 },
  { id: 'demo-park', name: 'Demo park', category: 'park', latitude: 31.8000, longitude: 35.2500 }
];

function distanceMeters(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }): number {
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const latitude = radians(b.latitude - a.latitude), longitude = radians(b.longitude - a.longitude);
  const square = Math.sin(latitude / 2) ** 2
    + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(longitude / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(square), Math.sqrt(Math.max(0, 1 - square)));
}

export const search: HanlinAssistantToolHandler<Arguments, Configuration> = (arguments_, { configuration }) => {
  const query = arguments_.query.trim().toLocaleLowerCase();
  return {
    demo: true,
    provider: 'local-fixtures',
    area: { ...configuration.area },
    places: fixtures.map(place => ({ ...place, distanceMeters: distanceMeters(configuration.area, place) }))
      .filter(place => configuration.categories.includes(place.category)
        && place.distanceMeters <= configuration.area.radiusMeters
        && (!query || (place.name + ' ' + place.category).toLocaleLowerCase().includes(query)))
  };
};
