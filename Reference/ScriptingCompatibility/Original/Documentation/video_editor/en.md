The `VideoEditor` API presents the system video trimming interface, letting users cut a video down to the part they want and returning the trimmed result to your script.

This API requires **Scripting PRO**.

---

## Namespace: `VideoEditor`

```ts
namespace VideoEditor
```

---

## Overview

* Presents a trimming interface for a video file, as a sheet by default or full screen on request
* Users can scrub, set the in/out points, preview, then confirm or cancel
* Resolves with the file path of the trimmed video, or `null` when the user cancels
* The trimmed video is written to a **new file in the temporary directory** — copy or move it if you need to keep it
* Only **one** editing interface can be presented at a time
* Requires a visible script UI, so it is not usable from widgets or notification scripts

---

## API Summary

| Method                          | Description                                             |
| ------------------------------- | ------------------------------------------------------- |
| `canEditVideo(filePath)`        | Checks whether a video can be trimmed                    |
| `present(options)`              | Presents the trimming interface and returns the result   |
| `dismiss()`                     | Closes the trimming interface                            |

---

## API Reference

### `canEditVideo(filePath: string): Promise<boolean>`

Checks whether the video at the given path can be trimmed.

#### Parameters

| Name       | Type     | Required | Description                        |
| ---------- | -------- | -------- | ---------------------------------- |
| `filePath` | `string` | Yes      | The file path of the video to check |

#### Return Value

* Resolves `true` when the video can be trimmed
* Resolves `false` when the file does not exist or its format is not supported
* Never throws, and does not require Scripting PRO

---

### `present(options: VideoEditorPresentOptions): Promise<string | null>`

Presents the video trimming interface.

#### Parameters

| Name                      | Type                 | Required | Description                                                                        |
| ------------------------- | -------------------- | -------- | ---------------------------------------------------------------------------------- |
| `options.filePath`        | `string`             | Yes      | The file path of the video to trim                                                 |
| `options.maximumDuration` | `number`             | No       | Maximum duration in seconds the trimmed video may have. Defaults to `600`. `0` means no limit |
| `options.quality`         | `VideoEditorQuality` | No       | Quality of the trimmed video. Defaults to `'medium'`                               |
| `options.fullScreen`      | `boolean`            | No       | Present the editor full screen. Defaults to `false`, which presents it as a sheet  |

`VideoEditorQuality` is one of:

```ts
type VideoEditorQuality =
  | 'high'
  | 'medium'
  | 'low'
  | '640x480'
  | 'iFrame1280x720'
  | 'iFrame960x540'
```

#### Return Value

* Resolves with the **file path of the trimmed video** when the user confirms
* Resolves with `null` when the user cancels, including when a sheet is swiped down to close
* Throws an error when:

  * `filePath` is missing or empty
  * No video exists at `filePath`
  * The video cannot be trimmed (see `canEditVideo`)
  * An editing interface is already presented
  * Trimming failed

#### Example

```ts
const editedPath = await VideoEditor.present({
  filePath: srcPath,
  maximumDuration: 60,
  quality: "high",
})

if (editedPath == null) {
  console.log("The user cancelled.")
} else {
  console.log("Trimmed video:", editedPath)
}
```

---

### `dismiss(): Promise<void>`

Closes the trimming interface opened by `present`.

#### Return Value

* Resolves once the interface has been closed
* Resolves immediately when nothing is presented

#### Usage Notes

* The pending `present` promise resolves with `null`, as if the user cancelled
* Manual dismissal is rarely needed; it is useful when a script has to close the interface on its own, for example after a timeout

---

## Usage Examples

### Example 1: Trim a video and save it

```ts
async function trimAndSave(srcPath: string) {
  if (!(await VideoEditor.canEditVideo(srcPath))) {
    console.error("This video cannot be trimmed.")
    return
  }

  const editedPath = await VideoEditor.present({ filePath: srcPath })
  if (editedPath == null) {
    return
  }

  const destPath = Path.join(FileManager.documentsDirectory, "trimmed.mov")
  await FileManager.copyFile(editedPath, destPath)
  console.log("Saved to:", destPath)
}
```

---

### Example 2: Limit the trimmed length

```ts
// Only allow a clip of up to 15 seconds, exported at low quality.
const clipPath = await VideoEditor.present({
  filePath: srcPath,
  maximumDuration: 15,
  quality: "low",
})
```

---

### Example 3: Trigger from a UI

```ts
import { Button, VStack } from "scripting"

function TrimButton({ filePath }: { filePath: string }) {
  return <VStack>
    <Button
      title="Trim Video"
      action={async () => {
        try {
          const editedPath = await VideoEditor.present({ filePath })
          console.log(editedPath ?? "cancelled")
        } catch (e) {
          console.error(String(e))
        }
      }}
    />
  </VStack>
}
```

---

## Errors and Considerations

### Common Errors

* **An editor is already presented** — wait for the previous `present` to settle, or call `dismiss()` first
* **No video found at the given path** — check the path with `FileManager` before calling
* **The video cannot be edited** — check with `canEditVideo` first

### Limitations

* Only trimming is supported; the interface does not offer other editing operations
* The result is always written to a new file — the source video is never modified
* The interface needs a visible script UI, so it cannot be used in widgets or notification scripts
* `maximumDuration` limits the length of the trimmed result, not the length of the source video
