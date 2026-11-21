@tool
class_name ProximityPreview3D
extends Node

## Alcance padrão das colocações sem classe de distância.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var radius_meters := 50.0
## Cada classe define em X a distância de carga e em Y a de descarga, em metros.
@export var distance_classes: Dictionary[StringName, Vector2] = {
	&"dist_near": Vector2(5, 7),
	&"dist_local": Vector2(25, 32),
	&"dist_mid": Vector2(50, 60),
	&"dist_away": Vector2(100, 115),
	&"dist_remote": Vector2(200, 220),
}
