// widget.tsx — Home Screen Widget for Nutrition Tracker
// This file now imports widget components from the widgetsize folder
import { Widget, Color } from "scripting"
import { SmallWidget } from "./widgetsize/SmallWidget"
import { MediumWidget } from "./widgetsize/MediumWidget"
import { LargeWidget } from "./widgetsize/LargeWidget"

const family = Widget.family

if (family === "systemLarge") {
  Widget.present(<LargeWidget />, {
    policy: "after",
    date: new Date(Date.now() + 1000 * 60 * 15),
  })
} else if (family === "systemMedium") {
  Widget.present(<MediumWidget />, {
    policy: "after",
    date: new Date(Date.now() + 1000 * 60 * 15),
  })
} else {
  Widget.present(<SmallWidget />, {
    policy: "after",
    date: new Date(Date.now() + 1000 * 60 * 15),
  })
}