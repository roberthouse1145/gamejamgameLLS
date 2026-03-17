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
