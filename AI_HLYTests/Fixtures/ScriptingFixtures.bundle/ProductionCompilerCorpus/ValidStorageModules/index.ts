import { Text as ScriptingText } from "scripting"
import payload from "./payload.json"
import { normalizedCount } from "./value"

Storage.clear()
Storage.set("test", { count: normalizedCount(payload.count) })
const value = Storage.get<{ count: number }>("test")
const bytes = Data.fromRawString(String(value?.count ?? 0))
if (bytes) Storage.setData("test-data", bytes)
const restored: Data | null = Storage.getData("test-data")

void ScriptingText
void restored
