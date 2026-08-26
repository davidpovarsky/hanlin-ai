`VideoEditor` API 用于唤起系统视频裁剪界面，让用户把视频剪成需要的片段，并把裁剪结果返回给脚本。

该 API 需要 **Scripting PRO**。

---

## 命名空间：`VideoEditor`

```ts
namespace VideoEditor
```

---

## 功能概述

* 展示指定视频文件的裁剪界面，默认以 sheet 形式，也可指定全屏
* 用户可以拖动时间轴设置起止点、预览，然后确认或取消
* 确认后返回裁剪结果的文件路径；用户取消时返回 `null`
* 裁剪结果会写入**临时目录中的新文件**，如需保留请自行拷贝或移动
* 同一时刻只能存在**一个**裁剪界面
* 需要有可见的脚本界面，因此不适用于小组件与通知脚本

---

## 方法一览

| 方法                       | 说明                |
| ------------------------ | ----------------- |
| `canEditVideo(filePath)` | 判断某个视频是否可以裁剪      |
| `present(options)`       | 展示裁剪界面并返回裁剪结果     |
| `dismiss()`              | 关闭裁剪界面            |

---

## 方法说明

### `canEditVideo(filePath: string): Promise<boolean>`

判断指定路径的视频是否可以裁剪。

#### 参数

| 参数         | 类型       | 必填 | 说明          |
| ---------- | -------- | -- | ----------- |
| `filePath` | `string` | 是  | 待检查视频的文件路径 |

#### 返回值

* 视频可以裁剪时 resolve `true`
* 文件不存在或格式不受支持时 resolve `false`
* 不会抛出错误，也不需要 Scripting PRO

---

### `present(options: VideoEditorPresentOptions): Promise<string | null>`

展示视频裁剪界面。

#### 参数

| 参数                        | 类型                   | 必填 | 说明                                        |
| ------------------------- | -------------------- | -- | ----------------------------------------- |
| `options.filePath`        | `string`             | 是  | 待裁剪视频的文件路径                                |
| `options.maximumDuration` | `number`             | 否  | 裁剪结果允许的最大时长（秒）。默认 `600`；传 `0` 表示不限制 |
| `options.quality`         | `VideoEditorQuality` | 否  | 裁剪结果的质量，默认 `'medium'`                     |
| `options.fullScreen`      | `boolean`            | 否  | 是否全屏展示编辑器。默认 `false`，即以 sheet 形式展示  |

`VideoEditorQuality` 取值如下：

```ts
type VideoEditorQuality =
  | 'high'
  | 'medium'
  | 'low'
  | '640x480'
  | 'iFrame1280x720'
  | 'iFrame960x540'
```

#### 返回值

* 用户确认时，resolve **裁剪结果的文件路径**
* 用户取消时，resolve `null`；以 sheet 展示时，下滑关闭同样按取消处理
* 以下情况会抛出错误：

  * 未传 `filePath` 或为空字符串
  * `filePath` 指向的文件不存在
  * 该视频无法裁剪（参见 `canEditVideo`）
  * 已经有一个裁剪界面在展示中
  * 裁剪失败

#### 示例

```ts
const editedPath = await VideoEditor.present({
  filePath: srcPath,
  maximumDuration: 60,
  quality: "high",
})

if (editedPath == null) {
  console.log("用户取消了。")
} else {
  console.log("裁剪结果：", editedPath)
}
```

---

### `dismiss(): Promise<void>`

关闭由 `present` 打开的裁剪界面。

#### 返回值

* 界面关闭后 resolve
* 当前没有展示中的界面时立即 resolve

#### 使用说明

* 处于 pending 状态的 `present` 会以 `null` resolve，等同于用户取消
* 一般不需要手动调用；适用于脚本需要自行关闭界面的场景，例如超时控制

---

## 使用示例

### 示例一：裁剪并保存视频

```ts
async function trimAndSave(srcPath: string) {
  if (!(await VideoEditor.canEditVideo(srcPath))) {
    console.error("该视频无法裁剪。")
    return
  }

  const editedPath = await VideoEditor.present({ filePath: srcPath })
  if (editedPath == null) {
    return
  }

  const destPath = Path.join(FileManager.documentsDirectory, "trimmed.mov")
  await FileManager.copyFile(editedPath, destPath)
  console.log("已保存到：", destPath)
}
```

---

### 示例二：限制裁剪长度

```ts
// 最多只允许剪出 15 秒的片段，并以低质量导出。
const clipPath = await VideoEditor.present({
  filePath: srcPath,
  maximumDuration: 15,
  quality: "low",
})
```

---

### 示例三：从界面触发

```ts
import { Button, VStack } from "scripting"

function TrimButton({ filePath }: { filePath: string }) {
  return <VStack>
    <Button
      title="裁剪视频"
      action={async () => {
        try {
          const editedPath = await VideoEditor.present({ filePath })
          console.log(editedPath ?? "已取消")
        } catch (e) {
          console.error(String(e))
        }
      }}
    />
  </VStack>
}
```

---

## 错误与注意事项

### 常见错误

* **已有裁剪界面在展示中** —— 等待上一次 `present` 结束，或先调用 `dismiss()`
* **指定路径下没有视频** —— 调用前先用 `FileManager` 确认路径
* **该视频无法裁剪** —— 先用 `canEditVideo` 检查

### 使用限制

* 仅支持裁剪，界面不提供其他编辑操作
* 结果始终写入新文件，源视频不会被修改
* 需要有可见的脚本界面，无法在小组件与通知脚本中使用
* `maximumDuration` 限制的是裁剪结果的长度，而不是源视频的长度
