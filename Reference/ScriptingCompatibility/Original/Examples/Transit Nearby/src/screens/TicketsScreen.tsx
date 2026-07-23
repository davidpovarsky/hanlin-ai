import { ContentUnavailableView, List, Section, Text } from "scripting"

export function TicketsScreen() {
  return (
    <List navigationTitle="כרטיסים" navigationBarTitleDisplayMode="large" listStyle="insetGroup" environments={{ layoutDirection: "rightToLeft" }}>
      <Section>
        <ContentUnavailableView
          title="כרטיסי התחבורה שלך"
          systemImage="ticket"
          description="ניהול ותשלום נסיעות יתווספו רק דרך ספק תשלומים מורשה."
        />
      </Section>
      <Section title="לתשומת לבך">
        <Text foregroundStyle="secondaryLabel">האפליקציה אינה שומרת פרטי תשלום או פרטי רב־קו.</Text>
      </Section>
    </List>
  )
}
