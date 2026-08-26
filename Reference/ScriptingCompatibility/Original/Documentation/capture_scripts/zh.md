HTTP 抓包脚本让你在抓包过程中用 JavaScript 改写匹配到的请求与响应。脚本挂在一条**抓包规则**上,当规则的 pattern 匹配到请求 URL 时,脚本便在抓包引擎内运行。

> 这些 API(`$request`、`$response`、`$done`、`$argument`、`console`、`$httpClient`、`$persistentStore`、`$notification`、`$utils`)**仅在抓包规则脚本中可用**——普通脚本里没有,也无需 import。

---

## 规则配置

每条规则在规则编辑器中配置:

| 字段 | 含义 |
| ---- | ---- |
| **Pattern** | 一个针对请求 URL 匹配的正则表达式。仅当匹配时脚本才运行。 |
| **Type** | `Request` 在请求发出前运行;`Response` 在收到响应后运行。 |
| **Requires Body** | 打开后会缓冲消息体,脚本得以读取并改写它;关闭时脚本只能看到 headers。 |
| **Max Body Size** | 超过此大小的 body 原样透传(该消息跳过脚本)。 |
| **Binary Body** | 打开时 `body` 以 `Uint8Array` 暴露;关闭时以字符串暴露。 |
| **Timeout** | 若脚本在此秒数内未调用 `$done(...)`,消息原样透传。 |
| **When the script cannot decide** | 脚本没能给出决定时,是放行(默认)还是拒绝。见[下文](#脚本没能给出决定时)。 |
| **Argument** | 以 `$argument` 暴露给脚本的值。 |

---

## 执行模型

当多条规则命中同一条消息时,它们**按列表中的先后顺序**依次运行,且效果累积:每个脚本都能看到上一个脚本的输出。请求脚本若返回 mock 响应(见下),则短路整条链——不再发起上游请求,也不再运行响应脚本。

若脚本抛错、超时或始终未调用 `$done(...)`,消息将原样透传 —— 脚本坏掉不会连带把流量弄断。当"被绕过"才是更坏的结果时,一条规则可以不要这个默认行为,见下文。

---

## 脚本没能给出决定时

默认情况下,一条给不出决定的规则会让流量原样通过。对大多数脚本这是对的默认值:其中某一个写错了,不该把它匹配到的 app 断掉。

但对那种**整条规则的存在意义就是改动流量**的脚本 —— 附带凭据、抹掉某个字段、拦住某样东西 —— 这个默认值是错的。在那里,"原样放行"意味着这条规则悄悄什么都没做,而另一头没有任何迹象看得出来。对这类规则,把 **When the script cannot decide** 设成 **Refuse traffic**,或者在模块里给这条规则写 `failure-policy=reject`。

### 什么算"没能给出决定"

不止是脚本抛错。以下几种都是"这条规则本该跑,而它没跑成":

* 脚本抛错,包括语法错误;
* 脚本始终没调用 `$done(...)`,到了 Timeout 被停;
* 脚本没能启动,或者引擎当时不可用;
* 这条规则**根本没有脚本正文** —— 模块规则的脚本一次都没下载下来(见下一节);
* body 超过了这条规则自己的 **Max Body Size**;
* body 攒不出来:响应是一段一段流式发过来的、或者超过了整条消息的缓冲上限、或者当时为脚本暂存的流量总量已经到顶。

★最后这一条值得多读一遍。**body 一旦攒不出来,这条消息上的规则一条都不会跑** —— 包括那些只看 headers、压根不需要 body 的规则。所以它是最容易让一条规则被悄悄绕过的情形,而且恰恰发生在你最希望规则看一眼的大文件传输上。

### 拒绝具体做什么

| 规则类型 | 拒绝 = |
| -------- | ------ |
| **Request** | 请求一个字节都不会发给服务器。app 收到一条本机生成的 **403**。 |
| **Response** | 服务器那条响应不交付。app 收到同样的 **403** 顶替它。 |

两个方向都回 403 而不是 502:出问题的不是服务器,是本地的一条规则。而响应侧是**换掉**而不是断开连接 —— 断开在 app 那边与网络本身出故障分不开,403 至少是认得出来的。

403 的正文是纯文本,写明是哪条规则、发生了什么。除此之外不带任何东西 —— 不带 URL、不带脚本路径、不带脚本产出的任何内容。这条正文会到达 app、并进入抓包记录,所以来自脚本的东西一律不许进去。

**由哪条规则说了算。** 当某条规则自己的脚本失败 —— 抛错、超时、没有正文可跑、或者 body 超过**那条规则**的 Max Body Size —— 由那条规则自己的设置决定。而当整条消息的 body 攒不出来时,这条消息上什么都没跑成,于是只要消息上**有任何一条**规则设成了拒绝,这条消息就被拒。

### 在模块里

把它当作脚本行上的一个键写下,与 `script-path` 等并列:

```
failure-policy=reject
```

写成 `reject` / `passthrough` 之外的值,导入模块时会被报告出来,该规则保持默认。

> **`failure-policy` 是本 app 自己的键。** 读同一种模块格式的其他 app 没有这个键。用了它的模块在这里按本文所述工作;而别的 app 拿到这个键会怎么办 —— 忽略、告警、还是整个拒掉这份模块 —— 不是本 app 能承诺的事。

它只对 request 与 response 规则有效。`failure-policy=reject` 写在定时、事件、DNS 或 rule 谓词脚本上时,导入时会报告并忽略:那几类没有可拒的流量,而且"拒绝"对它们各自的含义都不一样。

### 流式规则

带帧编解码器的规则在脚本给不出决定时一律放行,这个设置对它是灰的。等到那种脚本运行时,响应已经在发往 app 的路上了 —— 没有什么还能拒。

---

## 来自模块的脚本

模块用 `script-path` 声明它的脚本。模块导入或更新时,每一个都会被下载,并在**本机留一份副本**。真正运行的是那份副本 —— 改服务器上的文件不会有任何效果,直到这个模块下一次更新。

**脚本下载不下来时,规则照样会建出来,只是它没有正文。** 它会匹配、什么都不做 —— 而这与"规则正常工作、只是没什么可改"长得一模一样。"什么都不做"具体是什么,取决于规则类型:请求规则原样发出请求,响应规则原样交付响应,定时规则到点没有东西可跑,rule 谓词脚本被当成没匹配上。有三个地方能把它们分开:

* 模块列表会说这个模块有几条规则没有脚本正文;
* 模块详情页逐条说明:这条规则的脚本来自哪里、多大、上次更新是什么时候 —— 或者它没能下载下来、以及本该从哪下载;
* 脚本日志记下每一次下载与每一次失败的原因(分类 `fetch`)。

设成拒绝流量的规则是个例外:没有脚本正文时它回 403,而不是"什么都不做" —— 这正是设它的意义。见[脚本没能给出决定时](#脚本没能给出决定时)。

还有两件事值得知道:

* 来自模块的规则是只读的。想改的话,把模块复制成一份本地副本。
* 声明了**同一个** `script-path` 的两条规则共用一个 `$persistentStore` 默认槽位 —— "一个定时脚本刷新 token、一条请求规则使用它"这种常见写法正是靠它成立。见 [`$persistentStore`](capture_scripts_store/zh.md)。

---

## `$request`

在请求脚本与响应脚本中均可用。

```ts
$request: {
  url: string
  method: string
  headers: Record<string, string>
  body?: string | Uint8Array   // 仅当 Requires Body 打开时存在
}
```

在响应脚本中,`$request` 为只读,提供 `url` 与 `method` 作为上下文。

## `$response`

在响应脚本中可用。

```ts
$response: {
  status: number
  headers: Record<string, string>
  body?: string | Uint8Array   // 仅当 Requires Body 打开时存在
}
```

body 已经解压:若响应使用了 `Content-Encoding`(如 gzip),`body` 即为解码后的内容。仅当数据在**应用层**被 gzip 压缩时,才需要用 [`$utils.ungzip`](capture_scripts_utils/zh.md)。

---

## `$done`

每个脚本都必须调用一次 `$done(...)` 来结束。参数的形状决定结果。

### 请求脚本

```ts
// 原样透传
$done({})

// 改写发出的请求(任意字段可省略)
$done({
  url?: string,
  headers?: Record<string, string>,
  body?: string | Uint8Array,
})

// 直接返回 mock 响应,不联系服务器(短路整条链)
$done({
  response: {
    status: number,
    headers?: Record<string, string>,
    body?: string | Uint8Array,
  }
})
```

### 响应脚本

```ts
// 原样透传
$done({})

// 改写响应(任意字段可省略)
$done({
  status?: number,
  headers?: Record<string, string>,
  body?: string | Uint8Array,
})
```

当你返回 `headers` 时,它会替换掉转发出去的 header 集合;省略 `headers` 则保留原有的。

---

## `$argument`

规则上配置的值。普通 argument 是字符串;结构化 argument(input / select / switch 字段)则是一个以字段名为键的对象。

```ts
// 规则 argument: token=abc123
const token = $argument            // "abc123"

// 结构化 argument
const enabled = $argument.enabled  // true
```

---

## `console`

```ts
console.log(...args: any[]): void
```

`console.log` 会写入抓包日志,便于调试。

---

## 示例

```js
// 请求脚本: 注入一个 header 并加一个 query 标记。
const headers = $request.headers
headers["X-Debug"] = "1"
$done({ url: $request.url + "?trace=1", headers })
```

```js
// 响应脚本(Requires Body 打开): 给 JSON 响应加一个字段。
try {
  const json = JSON.parse($response.body)
  json.injected = true
  $done({ body: JSON.stringify(json) })
} catch (e) {
  $done({})
}
```

## 相关 API

* [`$httpClient`](capture_scripts_httpclient/zh.md) —— 在脚本中发起 HTTP 请求。
* [`$persistentStore`](capture_scripts_store/zh.md) —— 读写持久化的值。
* [`$notification`](capture_scripts_notification/zh.md) —— 发一条本地通知。
* [`$utils`](capture_scripts_utils/zh.md) —— 实用工具(`ungzip` 等)。
