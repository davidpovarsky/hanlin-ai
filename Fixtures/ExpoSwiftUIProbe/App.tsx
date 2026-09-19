import React, { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  Host,
  NavigationSplitView,
  NavigationStack,
  List,
  Section,
  Button,
  Text,
  Toggle,
  BottomSheet,
  HStack,
  VStack,
} from '@expo/ui/swift-ui';
import {
  navigationTitle,
  padding,
  foregroundStyle,
  font,
  listStyle,
  createModifier,
} from '@expo/ui/swift-ui/modifiers';

// Custom modifier registered in Swift via ViewModifierRegistry
export const navigationBarTitleDisplayMode = (mode: 'inline' | 'large' | 'automatic' = 'inline') =>
  createModifier('navigationBarTitleDisplayMode', { displayMode: mode });

export interface AppProps {
  variant?: 'A' | 'B';
}

const TORAH_BOOKS = [
  {
    id: 'genesis',
    name: 'בראשית',
    english: 'Genesis',
    sections: ['בראשית', 'נח', 'לך לך', 'וירא', 'חיי שרה', 'תולדות', 'ויצא'],
    sampleText: 'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃',
  },
  {
    id: 'exodus',
    name: 'שמות',
    english: 'Exodus',
    sections: ['שמות', 'וארא', 'בא', 'בשלח', 'יתרו', 'משפטים', 'תרומה'],
    sampleText: 'וְאֵ֗לֶּה שְׁמוֹת֙ בְּנֵ֣י יִשְׂרָאֵ֔ל הַבָּאִ֖ים מִצְרָ֑יְמָה אֵ֣ת יַעֲקֹ֔ב אִ֥ישׁ וּבֵית֖וֹ בָּֽאוּ׃',
  },
  {
    id: 'leviticus',
    name: 'ויקרא',
    english: 'Leviticus',
    sections: ['ויקרא', 'צו', 'שמיני', 'תזריע', 'מצורע', 'אחרי מות', 'קדושים'],
    sampleText: 'וַיִּקְרָ֖א אֶל־מֹשֶׁ֑ה וַיְדַבֵּ֤ר יְהֹוָה֙ אֵלָ֔יו מֵאֹ֥הֶל מוֹעֵ֖ד לֵאמֹֽר׃',
  },
  {
    id: 'benchmark1000',
    name: 'מבחן 1,000 שורות',
    english: '1,000 Rows Probe',
    sections: ['בדיקת עומס'],
    sampleText: 'מבחן ביצועים: טעינה וגלילה של 1,000 פריטי רשימה ב-SwiftUI',
  },
];

export default function App({ variant = 'A' }: AppProps) {
  const [selectedBookId, setSelectedBookId] = useState<string>('genesis');
  const [selectedSection, setSelectedSection] = useState<string>('בראשית');
  const [showSettingsSheet, setShowSettingsSheet] = useState<boolean>(false);
  const [showNikkud, setShowNikkud] = useState<boolean>(true);

  const currentBook = TORAH_BOOKS.find((b) => b.id === selectedBookId) ?? TORAH_BOOKS[0];

  return (
    <View style={styles.container}>
      <Host style={styles.host}>
        <NavigationSplitView
          columnVisibility="all"
          modifiers={[
            navigationTitle('Hanlin Sefaria Expo Reader'),
            navigationBarTitleDisplayMode('inline'),
          ]}
        >
          {/* 1. SIDEBAR COLUMN */}
          <NavigationSplitView.Sidebar>
            <NavigationStack modifiers={[navigationTitle('חומשי תורה')]}>
              <List modifiers={[listStyle('sidebar')]}>
                <Section title="ספרי תורה">
                  {TORAH_BOOKS.map((book) => (
                    <Button
                      key={book.id}
                      onPress={() => {
                        setSelectedBookId(book.id);
                        setSelectedSection(book.sections[0]);
                      }}
                    >
                      <HStack>
                        <Text modifiers={[font({ size: 18, weight: 'bold' })]}>{book.name}</Text>
                        <Text modifiers={[foregroundStyle('secondary'), font({ size: 14 })]}>
                          {'  '}({book.english})
                        </Text>
                      </HStack>
                    </Button>
                  ))}
                </Section>
                <Section title="גרסת זמן-ריצה">
                  <Text modifiers={[font({ size: 13 }), foregroundStyle('tint')]}>
                    {variant === 'A' ? '🟢 Expo Dynamic A' : '🔵 Expo Dynamic B'}
                  </Text>
                </Section>
              </List>
            </NavigationStack>
          </NavigationSplitView.Sidebar>

          {/* 2. CONTENT COLUMN */}
          <NavigationSplitView.Content>
            <NavigationStack modifiers={[navigationTitle(currentBook.name)]}>
              <List>
                <Section title="פרשיות השבוע">
                  {currentBook.sections.map((section) => (
                    <Button
                      key={section}
                      onPress={() => setSelectedSection(section)}
                    >
                      <Text
                        modifiers={[
                          font({
                            size: 16,
                            weight: selectedSection === section ? 'bold' : 'regular',
                          }),
                          foregroundStyle(selectedSection === section ? 'tint' : 'primary'),
                        ]}
                      >
                        {section}
                      </Text>
                    </Button>
                  ))}
                </Section>
              </List>
            </NavigationStack>
          </NavigationSplitView.Content>

          {/* 3. DETAIL COLUMN */}
          <NavigationSplitView.Detail>
            <NavigationStack
              modifiers={[
                navigationTitle(`${currentBook.name} — ${selectedSection}`),
                navigationBarTitleDisplayMode('inline'),
              ]}
            >
              <VStack modifiers={[padding({ all: 24 })]}>
                <HStack modifiers={[padding({ bottom: 16 })]}>
                  <Text
                    modifiers={[
                      font({ size: 28, weight: 'bold' }),
                      foregroundStyle('primary'),
                    ]}
                  >
                    {currentBook.name} : {selectedSection}
                  </Text>
                  <Button
                    onPress={() => {
                      setSelectedBookId('benchmark1000');
                      setSelectedSection('בדיקת עומס');
                    }}
                  >
                    <Text modifiers={[font({ size: 15 }), foregroundStyle('tint')]}>1,000 Rows Probe</Text>
                  </Button>
                  <Button onPress={() => setShowSettingsSheet(true)}>
                    <Text modifiers={[font({ size: 15 }), foregroundStyle('tint')]}>הגדרות</Text>
                  </Button>
                </HStack>

                {selectedBookId === 'benchmark1000' ? (
                  <VStack modifiers={[padding({ all: 8 })]}>
                    <Text modifiers={[font({ size: 18, weight: 'bold' }), padding({ bottom: 8 })]}>
                      רשימת 1,000 שורות SwiftUI פעילה
                    </Text>
                    <List>
                      {Array.from({ length: 1000 }, (_, i) => (
                        <Button key={i} onPress={() => {}}>
                          <HStack>
                            <Text modifiers={[font({ size: 15 })]}>שורה #{i + 1}</Text>
                            <Text modifiers={[foregroundStyle('secondary'), font({ size: 13 })]}>
                              {'  '}(פריט בדיקה {i + 1})
                            </Text>
                          </HStack>
                        </Button>
                      ))}
                    </List>
                  </VStack>
                ) : (
                  <VStack
                    modifiers={[
                      padding({ all: 16 }),
                      navigationTitle('טקסט מקור'),
                    ]}
                  >
                    <Text
                      modifiers={[
                        font({ size: 22 }),
                        foregroundStyle('primary'),
                      ]}
                    >
                      {showNikkud
                        ? currentBook.sampleText
                        : currentBook.sampleText.replace(/[\u0591-\u05C7]/g, '')}
                    </Text>
                  </VStack>
                )}

                <VStack modifiers={[padding({ top: 32 })]}>
                  <Text modifiers={[font({ size: 13 }), foregroundStyle('secondary')]}>
                    זוהי הרצת בדיקה דינמית של Expo / React Native UI בתוך Hanlin.
                  </Text>
                  <Text
                    modifiers={[
                      font({ size: 14, weight: 'semibold' }),
                      foregroundStyle(variant === 'A' ? 'green' : 'blue'),
                    ]}
                  >
                    {variant === 'A'
                      ? 'מצב פעיל: Expo Dynamic A (Initial MiniApp)'
                      : 'מצב פעיל: Expo Dynamic B (Hot-Replaced MiniApp)'}
                  </Text>
                </VStack>

                {/* BottomSheet settings modal */}
                <BottomSheet
                  isPresented={showSettingsSheet}
                  onDismiss={() => setShowSettingsSheet(false)}
                >
                  <VStack modifiers={[padding({ all: 20 })]}>
                    <Text modifiers={[font({ size: 20, weight: 'bold' }), padding({ bottom: 12 })]}>
                      הגדרות קריאה
                    </Text>
                    <Toggle
                      isOn={showNikkud}
                      onIsOnChange={setShowNikkud}
                      title="הצג ניקוד וטעמים"
                    />
                    <Button onPress={() => setShowSettingsSheet(false)}>
                      <Text modifiers={[padding({ top: 16 }), foregroundStyle('tint')]}>סגור</Text>
                    </Button>
                  </VStack>
                </BottomSheet>
              </VStack>
            </NavigationStack>
          </NavigationSplitView.Detail>
        </NavigationSplitView>
      </Host>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  host: {
    flex: 1,
  },
});
