import {
  Divider,
  Grid,
  GridRow,
  Image,
  LiveActivity,
  LiveActivityUI,
  LiveActivityUIExpandedBottom,
  LiveActivityUIExpandedCenter,
  LiveActivityUIExpandedLeading,
  LiveActivityUIExpandedTrailing,
  ProgressView,
  Text,
  TimerIntervalLabel,
  type LiveActivityUIBuilder,
} from "scripting"
import { TransitTheme } from "./src/design/TransitTheme"
import type { TransitActivityState } from "./src/domain/models"

export const TRANSIT_ACTIVITY_NAME = "TransitNearbyArrival"

function Countdown({ expectedAt, font = "headline" }: { expectedAt: number; font?: "headline" | "title2" }) {
  return (
    <TimerIntervalLabel
      from={new Date()}
      to={new Date(Math.max(Date.now(), expectedAt))}
      countsDown
      showsHours={false}
      monospacedDigit
      font={font}
      fontWeight="bold"
    />
  )
}

function ActivityRouteBadge({ number }: { number: string }) {
  return (
    <Text
      font="title2"
      fontWeight="bold"
      monospacedDigit
      foregroundStyle="white"
      padding={{ horizontal: 10, vertical: 6 }}
      background={{ style: TransitTheme.activityPurple, shape: { type: "rect", cornerRadius: 8 } }}
    >{number}</Text>
  )
}

function LockScreenContent(state: TransitActivityState) {
  const progress = state.distanceFromStop == null
    ? 0.5
    : Math.max(0.05, Math.min(1, 1 - state.distanceFromStop / 2_000))
  const extra = state.upcoming.slice(1, 3)
  return (
    <Grid
      alignment="trailing"
      horizontalSpacing={10}
      verticalSpacing={7}
      padding={14}
      foregroundStyle="white"
      activityBackgroundTint="black"
      activitySystemActionForegroundColor="white"
      environments={{ layoutDirection: "rightToLeft" }}
    >
      <GridRow alignment="center">
        <ActivityRouteBadge number={state.routeNumber} />
        <Grid alignment="trailing" verticalSpacing={2} frame={{ maxWidth: "infinity", alignment: "trailing" }}>
          <GridRow><Text font="headline" fontWeight="bold" lineLimit={1}>{state.headsign}</Text></GridRow>
          <GridRow><Text font="caption" foregroundStyle="#D3D3D8" lineLimit={1}>{state.stopName}</Text></GridRow>
        </Grid>
        <Grid alignment="leading" verticalSpacing={2}>
          <GridRow><Text font="caption" foregroundStyle="#D3D3D8">עוד</Text></GridRow>
          <GridRow><Countdown expectedAt={state.expectedAt} font="title2" /></GridRow>
          {state.delayMinutes && state.delayMinutes > 0 ? (
            <GridRow><Text font="caption" foregroundStyle={TransitTheme.warning}>עיכוב קל</Text></GridRow>
          ) : null}
        </Grid>
      </GridRow>
      <ProgressView value={progress} progressViewStyle="linear" tint={TransitTheme.activityPurple} gridCellColumns={3} />
      {extra.length > 0 ? <Divider gridCellColumns={3} opacity={0.3} /> : null}
      {extra.map(arrival => (
        <GridRow key={`${arrival.routeNumber}:${arrival.expectedAt}`}>
          <Text
            font="caption"
            fontWeight="bold"
            foregroundStyle="white"
            padding={{ horizontal: 6, vertical: 2 }}
            background={{ style: TransitTheme.activityPurple, shape: { type: "rect", cornerRadius: 5 } }}
          >{arrival.routeNumber}</Text>
          <Text font="caption" lineLimit={1}>{arrival.headsign}</Text>
          <TimerIntervalLabel
            from={new Date()}
            to={new Date(Math.max(Date.now(), arrival.expectedAt))}
            countsDown
            showsHours={false}
            monospacedDigit
            font="caption"
            foregroundStyle={arrival.realtime ? "systemGreen" : "#D3D3D8"}
          />
        </GridRow>
      ))}
    </Grid>
  )
}

const builder: LiveActivityUIBuilder<TransitActivityState> = state => {
  const progress = state.distanceFromStop == null
    ? 0.5
    : Math.max(0.05, Math.min(1, 1 - state.distanceFromStop / 2_000))
  return (
    <LiveActivityUI
      content={<LockScreenContent {...state} />}
      compactLeading={<Text font="headline" fontWeight="bold" foregroundStyle="white" padding={{ horizontal: 7, vertical: 2 }} background={{ style: TransitTheme.activityPurple, shape: "capsule" }}>{state.routeNumber}</Text>}
      compactTrailing={<Countdown expectedAt={state.expectedAt} />}
      minimal={<Image systemName="bus.fill" foregroundStyle={TransitTheme.activityPurple} />}
    >
      <LiveActivityUIExpandedLeading>
        <ActivityRouteBadge number={state.routeNumber} />
      </LiveActivityUIExpandedLeading>
      <LiveActivityUIExpandedTrailing>
        <Countdown expectedAt={state.expectedAt} font="title2" />
      </LiveActivityUIExpandedTrailing>
      <LiveActivityUIExpandedCenter>
        <Grid alignment="trailing" verticalSpacing={2} environments={{ layoutDirection: "rightToLeft" }}>
          <GridRow><Text font="headline" fontWeight="bold">{state.headsign}</Text></GridRow>
          <GridRow><Text font="caption" foregroundStyle="secondaryLabel">התחנה הבאה בעוד זמן קצר</Text></GridRow>
        </Grid>
      </LiveActivityUIExpandedCenter>
      <LiveActivityUIExpandedBottom>
        <Grid alignment="trailing" verticalSpacing={6} environments={{ layoutDirection: "rightToLeft" }}>
          <ProgressView value={progress} progressViewStyle="linear" tint={TransitTheme.activityPurple} />
          <GridRow>
            <Image systemName="bus.fill" foregroundStyle={TransitTheme.activityPurple} />
            <Text font="caption" lineLimit={1}>{state.stopName}</Text>
          </GridRow>
        </Grid>
      </LiveActivityUIExpandedBottom>
    </LiveActivityUI>
  )
}

export const TransitArrivalActivity = LiveActivity.register<TransitActivityState>(TRANSIT_ACTIVITY_NAME, builder)
