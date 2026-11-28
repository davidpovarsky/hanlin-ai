import { ContentUnavailableView, List, NavigationLink, Section } from "scripting"
import { RouteRow } from "../components/TransitRows"
import type { TransitRoute } from "../domain/models"
import { getCachedBoard, getRecentStops } from "../storage/transitStorage"
import { RouteDetailsScreen } from "./RouteDetailsScreen"

export function RoutesScreen() {
  const routes = getRecentStops()
    .flatMap(stop => getCachedBoard(stop.code)?.routes ?? [])
    .filter((route, index, all) => all.findIndex(item => item.id === route.id) === index)
  return (
    <List
      navigationTitle="מסלולים"
      navigationBarTitleDisplayMode="large"
      listStyle="insetGroup"
      environments={{ layoutDirection: "rightToLeft" }}
      overlay={routes.length === 0 ? (
        <ContentUnavailableView title="אין קווים אחרונים" systemImage="bus" description="פתח תחנה כדי להציג את הקווים העוברים בה" />
      ) : undefined}
    >
      <Section title="קווים אחרונים">
        {routes.map((route: TransitRoute) => (
          <NavigationLink key={route.id} destination={<RouteDetailsScreen route={route} />}>
            <RouteRow route={route} />
          </NavigationLink>
        ))}
      </Section>
    </List>
  )
}
