class_name AppDefinition extends Resource
## APP定义资源，描述APP的元信息（名称、图标、入口场景等）
## 用于AppManager注册和管理应用程序

## 应用唯一标识符
@export var app_id: String = ""

## 应用显示名称
@export var app_name: String = ""

## 应用图标
@export var icon: Texture2D

## 应用入口场景
@export var entry_scene: PackedScene

## Web 快捷应用入口。设置后复用浏览器窗口打开该地址，无需单独入口场景。
@export var launch_url: String = ""

## 是否在桌面创建图标
@export var show_on_desktop: bool = true

## 窗口约束配置
@export var window_constraints: Resource  # WindowConstraints
