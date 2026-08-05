class_name WebPageResource
extends Resource

## 网页 URL（用于路由匹配）
@export var url: String = ""

## 网页标题
@export var title: String = ""

## 浏览器标签页显示的站点图标。
@export_file var icon_path: String = ""

## 网页摘要（搜索结果展示 + AI 生成参考）
@export_multiline var hint: String = ""

## 页面 DSL 内容（为空则由 AI 生成）
@export_multiline var content: String = ""

## Prebuilt scene page path. When set, BrowserApp instantiates this scene
## directly instead of rendering DSL content.
@export_file("*.tscn") var scene_path: String = ""

## AI 生成时的补充指令（content 为空时使用）
@export_multiline var design_prompt: String = ""

## 是否允许通过搜索出现。关闭后只能通过页面跳转进入。
@export var searchable: bool = true

## 搜索出现条件（全部满足才可出现）。
## source 可取 browser、state、story；field 使用对应数据中的点分路径。
## 例：{"source":"story","field":"chapter_opened","op":"==","value":true}
@export var search_conditions: Array[Dictionary] = []

## 搜索关键词（命中这些词时出现在搜索结果中）
@export var search_keywords: PackedStringArray = []

## 页面内超链接对应的 URL 列表（用于预加载等）
@export var linked_urls: PackedStringArray = []
