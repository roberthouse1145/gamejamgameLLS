# AVG DSL 画面语义

本项目里，背景、角色立绘、普通图片、CG 是四种不同的演出语义。

## 区分原则

- 背景：场景底图，使用 bg.show(...)
- 角色：角色立绘，由 character 系统驱动，使用 char_xxx.show(...)、expression、outfit
- 普通图片：额外插图、照片、道具图、说明图，使用 image.show(...)
- CG：全屏事件图，使用 cg.show(...)

## 为什么图片和 CG 不合并成一个词

- 从资源类型上看，CG 也是图片的一种
- 从 DSL 语义上看，CG 表示“全屏事件画面”
- 普通图片表示“插入到舞台中的非角色图片”

因此底层都可以映射到 SHOW_IMAGE，但 DSL 应保留两层语义：

- image.show(...)：舞台图片
- cg.show(...)：全屏 CG

## DSL 用法

### 背景

bg.show("bg_park_grass", fade_duration=0.4)

### 角色

char_001.show(position="center", outfit="casual", emotion="happy")
char_001.expression = "surprised"
char_001.change_outfit(outfit="maid", emotion="happy")

### 普通图片

image.show("photo_001", position="left")
image.show("item_poster", position="center", size="medium")
image.hide("photo_001")

约定：

- 适合局部插图、照片、票据、海报、道具特写
- 默认不是全屏
- 推荐 position 使用 left、center、right

### CG

cg.show("cg_event_001")
cg.hide()

约定：

- 默认全屏
- 用于关键事件、回忆、高潮演出、特殊过场
- 不用于角色常驻立绘

## 素材清单规则

- list_assets 可以列出 backgrounds、images、cg、bgm、sfx、characters
- characters 只提供角色 ID、表情、服装，不列出角色立绘文件本身
- images 和 cg 只列非角色图片资源

## 推荐目录结构

推荐把图片资源放在模板项目的这些目录下：

- 背景：templates/tutorial_project/assets/images/background
- 角色立绘：templates/tutorial_project/assets/images/character
- 普通图片：templates/tutorial_project/assets/images/illustrations
- 普通图片：templates/tutorial_project/assets/images/props
- 普通图片：templates/tutorial_project/assets/images/photos
- CG：templates/tutorial_project/assets/images/cg

其中：

- background 只给 bg.show(...) 使用
- character 只给角色系统使用，不给 image.show(...) 或 cg.show(...)
- illustrations、props、photos 会被识别为普通图片来源
- cg 会被识别为 CG 来源

## alias 模板示例

可以在 templates/tutorial_project/manifests/asset_aliases.json 里这样登记：

{
	"images": {
		"date_photo_001": "assets/images/photos/date_photo_001.png",
		"poster_cafe_menu": "assets/images/illustrations/poster_cafe_menu.png",
		"cg_evening_walk": "assets/images/cg/cg_evening_walk.png"
	}
}

约定：

- 普通图片 alias 建议用功能名或内容名
- CG alias 建议以 cg_ 开头
- 没有 alias 时，也可以直接使用素材清单里列出的原始文件名

## 禁止事项

- 不要把角色立绘资源当作 image.show(...) 或 cg.show(...) 的输入
- 不要在 DSL 中写 res:// 完整路径
- 优先使用 alias；没有 alias 时再使用素材清单里的原始资源名