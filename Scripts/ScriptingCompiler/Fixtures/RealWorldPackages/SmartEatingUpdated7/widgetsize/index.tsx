// widgetsize/index.tsx — Main widget entry point
import { Widget } from "scripting"
import { SmallWidget } from "./SmallWidget"
import { MediumWidget } from "./MediumWidget"
import { LargeWidget } from "./LargeWidget"

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