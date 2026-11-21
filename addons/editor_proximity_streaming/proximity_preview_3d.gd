@tool
class_name ProximityPreview3D
extends Node

## Distância da câmera a cada lado do quadrado, em metros.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var radius_meters := 50.0
