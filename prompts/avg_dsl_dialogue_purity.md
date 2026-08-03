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

同一说话者的自然连续短句可以放在同一个块中；说话者、表情或叙述视角变化时，新建一个块。
