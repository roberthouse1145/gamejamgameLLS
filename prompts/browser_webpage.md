根据本轮网址、页面内容目标与视觉方向，编写一张完整的虚拟网页快照。

输出使用 PageMark。可用结构如下：

- `::: col`、`::: row`、`::: card`、`::: grid cols=N`、`::: form action=name` 容器，均用独立一行 `:::` 闭合。
- `#` 至 `####` 标题、普通段落、列表、引用和 `---` 分隔线。
- `[文字](url:目标)` 网页链接。
- `[文字](action:动作名)` 操作按钮。
- 表单内使用 `input field=name`、`textarea field=name`、`select field=name options=A|B`、`checkbox field=name`。
- 容器属性可使用 `fill`、`width`、`height`、`sep`、`pad`、`bg`、`border` 和 `corner_radius`。

页面正文具有明确标题、完整信息层级和足够内容。首行直接进入 PageMark 页面结构。

最小输出示例：

```text
::: col fill sep=12
# 页面标题

页面正文。

[返回首页](url:browser://home)
:::
```
