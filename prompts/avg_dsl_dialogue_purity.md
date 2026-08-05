# 台词与旁白

`TextBlock(speaker="...")` 下的每一行 `>` 只写该说话者真正说出口的话。

动作、表情和舞台变化使用对应演出命令：

```text
CharacterA.effect("nod")
# => TextBlock(speaker="CharacterA")
> 嗯。
```

第三人称叙述、环境描写和无法用命令表达的动作放入无 `speaker` 的旁白块：

```text
CharacterA.hide(exit_effect="fade")
# => TextBlock()
> 那个人离开了画面。
```

## 对话框阅读节奏

- 一个 `TextBlock` 只承载一个阅读节拍，正文以 18–32 个汉字为目标。
- 每个块使用一至两行 `>`；每行约 12–24 个汉字，并在自然停顿处换行。
- 信息较长时，按语气、动作反应或含义转折拆成连续的 `TextBlock`，让玩家点击后逐拍阅读。
- 说话者、表情或叙述视角变化时，新建一个块。

```text
# => TextBlock(speaker="CharacterA")
> 我知道这听起来很突然。
> 先让我把最重要的事说清楚。
# => TextBlock(speaker="CharacterA")
> 剩下的，我们可以慢慢谈。
```
