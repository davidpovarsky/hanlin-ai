import { ContentUnavailableView, List, NavigationLink, RoundedRectangle, Section, useState } from "scripting"
import { AlertRow, RouteRow, StopCard } from "../components/TransitRows"
import { TransitTheme } from "../design/TransitTheme"
import type { StopBoard, TransitRoute, TransitStop } from "../domain/models"
import { getCachedBoard, getFavoriteRoutes, getFavorites } from "../storage/transitStorage"
import { RouteDetailsScreen } from "./RouteDetailsScreen"
import { loadStopBoard } from "../data/transitRepository"
import { StopDetailsScreen } from "./StopDetailsScreen"

export function FavoritesScreen() {
  const [favorites, setFavorites] = useState<TransitStop[]>(getFavorites())
  const [favoriteRoutes, setFavoriteRoutes] = useState<TransitRoute[]>(getFavoriteRoutes())
  const [boards, setBoards] = useState<Record<string, StopBoard>>({})

  async function refreshFavorites() {
    const stops = getFavorites()
    setFavorites(stops)
    setFavoriteRoutes(getFavoriteRoutes())
    const loaded = await Promise.allSettled(stops.slice(0, 8).map(loadStopBoard))
    const values = loaded.flatMap(result => result.status === "fulfilled" ? [result.value] : [])
    setBoards(Object.fromEntries(values.map(board => [board.stop.code, board])))
  }

  const currentAlerts = favorites.flatMap(stop => boards[stop.code]?.alerts ?? getCachedBoard(stop.code)?.alerts ?? [])
    .filter((alert, index, all) => all.findIndex(item => item.id === alert.id) === index)
    .slice(0, 3)
  return (
    <List
      navigationTitle="מועדפים"
      navigationBarTitleDisplayMode="large"
      listStyle="insetGroup"
      listRowSpacing={8}
      scrollContentBackground="hidden"
      background={TransitTheme.groupedBackground}
      environments={{ layoutDirection: "rightToLeft" }}
      onAppear={() => void refreshFavorites()}
      overlay={favorites.length === 0 && favoriteRoutes.length === 0 ? (
        <ContentUnavailableView
          title="אין תחנות מועדפות"
          systemImage="star"
          description="אפשר להוסיף תחנה ממסך פרטי התחנה"
        />
      ) : undefined}
    >
      {currentAlerts.length > 0 ? (
        <Section title="עדכוני שירות">
          {currentAlerts.map(alert => <AlertRow key={alert.id} transitAlert={alert} />)}
        </Section>
      ) : null}
      {favorites.length > 0 ? <Section title="התחנות שלך">
        {favorites.map(stop => (
          <NavigationLink
            key={stop.code}
            destination={<StopDetailsScreen stop={stop} />}
            listRowInsets={{ top: 2, bottom: 2, leading: 12, trailing: 12 }}
            listRowSeparator="hidden"
            listRowBackground={<RoundedRectangle cornerRadius={13} fill={TransitTheme.card} />}
          >
            <StopCard stop={stop} board={boards[stop.code] ?? getCachedBoard(stop.code)} />
          </NavigationLink>
        ))}
      </Section> : null}
      {favoriteRoutes.length > 0 ? (
        <Section title="קווים מועדפים">
          {favoriteRoutes.map(route => (
            <NavigationLink key={route.id} destination={<RouteDetailsScreen route={route} />}>
              <RouteRow route={route} />
            </NavigationLink>
          ))}
        </Section>
      ) : null}
    </List>
  )
}
