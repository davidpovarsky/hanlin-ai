import { Navigation, Script } from "scripting"
import { TransitNearbyApp } from "./src/app/App"

async function run() {
  await Navigation.present({
    element: <TransitNearbyApp />,
    modalPresentationStyle: "fullScreen",
  })
  Script.exit()
}

run().catch(error => {
  console.error(error instanceof Error ? error.message : String(error))
  Script.exit()
})
