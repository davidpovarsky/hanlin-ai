import { Grid, GridRow, Label, List, Section, Text } from "scripting"
import { RouteBadge } from "../components/TransitRows"
import type { JourneyPlan } from "../domain/models"
import { shortTime } from "../utils/dates"

export function JourneyRow({ journey }: { journey: JourneyPlan }) {
  const routeNumbers = journey.legs.flatMap(leg => leg.routeNumber ? [leg.routeNumber] : [])
  return (
    <Grid alignment="trailing" horizontalSpacing={10} verticalSpacing={5} padding={{ vertical: 6 }}>
      <GridRow>
        <Text font="headline" fontWeight="bold" monospacedDigit>{shortTime(journey.startAt)}–{shortTime(journey.endAt)}</Text>
        <Text frame={{ maxWidth: "infinity", alignment: "trailing" }}>{Math.round(journey.durationSeconds / 60)} דקות</Text>
      </GridRow>
      <GridRow>
        <Text foregroundStyle="secondaryLabel">{journey.transfers === 0 ? "ללא החלפה" : `${journey.transfers} החלפות`}</Text>
        <Text foregroundStyle="secondaryLabel">הליכה {Math.round(journey.walkDurationSeconds / 60)} דק׳</Text>
      </GridRow>
      <GridRow>
        <Text gridCellColumns={2}>{routeNumbers.length ? routeNumbers.map(number => `קו ${number}`).join(" ← ") : "מסלול הליכה"}</Text>
      </GridRow>
    </Grid>
  )
}

export function JourneyDetailScreen({ journey }: { journey: JourneyPlan }) {
  return (
    <List navigationTitle="פרטי מסע" navigationBarTitleDisplayMode="inline" listStyle="insetGroup" environments={{ layoutDirection: "rightToLeft" }}>
      <Section title="סיכום">
        <Label title={`${shortTime(journey.startAt)} עד ${shortTime(journey.endAt)}`} systemImage="clock" />
        <Label title={`${Math.round(journey.durationSeconds / 60)} דקות`} systemImage="hourglass" />
        <Label title={`${journey.transfers} החלפות`} systemImage="arrow.left.arrow.right" />
      </Section>
      <Section title="שלבי הנסיעה">
        {journey.legs.map((leg, index) => (
          <Grid key={leg.id} alignment="trailing" horizontalSpacing={10} verticalSpacing={4} padding={{ vertical: 7 }}>
            <GridRow>
              {leg.routeNumber ? <RouteBadge number={leg.routeNumber} /> : <Label title="הליכה" systemImage="figure.walk" />}
              <Text font="headline" frame={{ maxWidth: "infinity", alignment: "trailing" }}>{leg.headsign || `${leg.fromName} ← ${leg.toName}`}</Text>
              <Text monospacedDigit>{shortTime(leg.startAt)}</Text>
            </GridRow>
            <GridRow>
              <Text>{""}</Text>
              <Text foregroundStyle="secondaryLabel">{leg.fromName} ← {leg.toName}</Text>
              <Text foregroundStyle="secondaryLabel">{Math.round(leg.durationSeconds / 60)} דק׳</Text>
            </GridRow>
            {leg.intermediateStopNames.length > 0 ? (
              <GridRow><Text gridCellColumns={3} font="caption" foregroundStyle="secondaryLabel">{leg.intermediateStopNames.length} תחנות ביניים</Text></GridRow>
            ) : null}
          </Grid>
        ))}
      </Section>
    </List>
  )
}
