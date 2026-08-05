根据本轮网址、页面内容目标与视觉方向，编写一张完整的虚拟网页快照。

输出使用 PageMark。可用结构如下：

- `::: col`、`::: row`、`::: card`、`::: grid cols=N`、`::: form action=name` 容器，均用独立一行 `:::` 闭合。
- 现代网站的全宽内容带使用 `::: section bg=#FFFFFF max_width=1800 pad=32`，section 会让正文在宽屏中居中并保持阅读宽度。
- 文档页面可使用 `::: pdf filename="文件名.pdf" pages="1 / 1"` 作为查看器，内部使用 `::: document width=1380 pad=88` 表示纸张。
- 正式文书中的表格使用 `::: table cols=N`，每个表格项使用 `::: cell pad=18`。
- `#` 至 `####` 标题、普通段落、列表、引用和 `---` 分隔线。
- `[文字](url:目标)` 网页链接。
- `[文字](action:动作名)` 操作按钮。
- `![说明](image:src=res://资源路径 width=宽度 height=高度)` 页面图片。
- 表单内使用 `input field=name`、`textarea field=name`、`select field=name options=A|B`、`checkbox field=name`。
- 容器属性可使用 `fill`、`width`、`height`、`sep`、`pad`、`bg`、`border` 和 `corner_radius`；card 可使用 `shadow=false` 与 `border_width=1`。

页面正文具有明确标题、完整信息层级和足够内容。首行直接进入 PageMark 页面结构。

最小输出示例：

```text
::: col fill sep=12
# 页面标题

页面正文。

[返回首页](url:browser://home)
:::
```

文档页面最小示例：

```text
::: pdf filename="录用通知书.pdf" pages="1 / 1"
::: document width=1380 pad=88
# [center]录用通知书[/center]

::: table cols=2
::: cell
岗位
:::
::: cell
内容运营
:::
:::
:::
:::
```
