class_name WindowConstraints extends Resource
## 窗口约束资源，存储窗口大小和行为约束
## 用于定义应用程序窗口的尺寸限制和调整行为

## 窗口最小尺寸
@export var min_size: Vector2 = Vector2(200, 150)

## 窗口最大尺寸（Vector2.ZERO 表示无限制）
@export var max_size: Vector2 = Vector2.ZERO

## 窗口是否可调整大小
@export var resizable: bool = true

## 窗口创建时的默认尺寸
@export var default_size: Vector2 = Vector2(800, 600)

## 相对可用区域的默认尺寸比例（0 表示禁用，使用 default_size）
@export_range(0.0, 1.0, 0.01) var default_size_ratio: float = 0.0

## 内容区默认宽高比（0 表示不调整，适合需要无黑边的播放器窗口）
@export var default_content_aspect_ratio: float = 0.0
