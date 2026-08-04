# 角色立绘目录

角色素材使用稳定角色键组织：

- `ruan_yunyou/`：阮云柚
- `lu_yuanyuan/`：陆鸢鸢

目录结构：

```text
<character_key>/<outfit>/expression_01.png ... expression_32.png
```

每套服装的 32 张图片使用同一套表情序号。当前没有可靠的原始表情命名表，因此文件名保留客观序号，不猜测表情语义；游戏资源通过 `emotion_slots` 把语义名称映射到序号。

服装目录：

- `bath`
- `casual`
- `casual_damaged`
- `casual_heavy_damaged`
- `loungewear`
- `maid`
- `nude`
- `school`
- `school_damaged`
- `school_heavy_damaged`
- `sexy`
- `swimsuit`
- `underwear`

原始素材映射：

- `女主/hotaru_*` → `ruan_yunyou/`
- `青梅/setsuna_*` → `lu_yuanyuan/`
- `_d` → `_damaged`
- `_hd` → `_heavy_damaged`
