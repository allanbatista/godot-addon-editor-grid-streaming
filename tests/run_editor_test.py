import json
import os
from pathlib import Path
from shutil import copyfile, copytree
import subprocess
import tempfile

REPOSITORY = Path(__file__).resolve().parent.parent

PROJECT = """config_version=5

[application]
config/name="Editor Proximity Streaming Test"

[editor_plugins]
enabled=PackedStringArray("res://addons/editor_proximity_streaming/plugin.cfg", "res://addons/test_probe/plugin.cfg")

[rendering]
renderer/rendering_method="gl_compatibility"
"""

WORLD = """[gd_scene format=3]

[ext_resource type="Script" path="res://addons/editor_proximity_streaming/proximity_placement_3d.gd" id="1"]
[ext_resource type="Script" path="res://addons/editor_proximity_streaming/proximity_preview_3d.gd" id="2"]

[node name="World" type="Node3D"]

[node name="Preview" type="Node" parent="."]
script = ExtResource("2")
radius_meters = 10.0
"""

PREFAB = """[gd_scene format=3]

[sub_resource type="BoxMesh" id="BoxMesh_1"]
size = Vector3(2, 2, 2)

[node name="Prefab" type="Node3D"]

[node name="Building" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_1")
"""

PLACEMENTS = (
    ("Near", 2, 2),
    ("Diagonal", 10, 10),
    ("LeftEdge", -10, 0),
    ("Overlap", 15, 0),
    ("Beyond", 10.2, 0),
    ("Far", 200, 0),
)


def create_fixture(project):
    addon = "editor_proximity_streaming"
    copytree(REPOSITORY / "addons" / addon, project / "addons" / addon)
    probe = project / "addons" / "test_probe"
    probe.mkdir()
    (probe / "plugin.cfg").write_text('[plugin]\nname="Test Probe"\nscript="editor_test.gd"\n')
    copyfile(REPOSITORY / "tests" / "editor_test.gd", probe / "editor_test.gd")
    (project / "project.godot").write_text(PROJECT)
    for name in ("near", "far"):
        (project / f"{name}.tscn").write_text(PREFAB)
    world = WORLD
    for name, x, z in PLACEMENTS:
        prefab = "far" if name == "Far" else "near"
        world += (
            f'\n[node name="{name}" type="Node3D" parent="."]\n'
            f'position = Vector3({x}, 0, {z})\nscript = ExtResource("1")\n'
            f'scene_path = "res://{prefab}.tscn"\n'
        )
        if name == "Overlap":
            world += "metadata/stream_bounds = AABB(-5, -1, -1, 10, 2, 2)\n"
    (project / "world.tscn").write_text(world)


def create_class_fixture(project):
    locations = {
        "NearLimit": ("res://class_near.tscn", 5, ""),
        "LocalLimit": ("res://near.tscn", 25, "dist_local"),
        "MidLimit": ("res://near.tscn", 50, "dist_mid"),
        "AwayLimit": ("res://near.tscn", 100, "dist_away"),
        "RemoteLimit": ("res://near.tscn", 200, "dist_remote"),
        "CustomLimit": ("res://near.tscn", 12, "dist_custom"),
        "Room": ("res://room.tscn", 0, "dist_local"),
    }
    class_root = WORLD.replace('radius_meters = 10.0', 'radius_meters = 1.0')
    for name, (path, x, stream_class) in locations.items():
        class_root += (
            f'\n[node name="{name}" type="Node3D" parent="."]\n'
            f'position = Vector3({x}, 0, 0)\nscript = ExtResource("1")\nscene_path = "{path}"\n'
            f'stream_class = &"{stream_class}"\n'
        )
    (project / "classes.tscn").write_text(class_root)
    (project / "class_near.tscn").write_text(PREFAB.replace(
        '[node name="Prefab" type="Node3D"]',
        '[node name="Prefab" type="Node3D" groups=["world_object"]]\nmetadata/stream_class = "dist_near"',
    ))
    (project / "detail.tscn").write_text(PREFAB)
    (project / "room.tscn").write_text(
        '[gd_scene format=3]\n\n'
        '[ext_resource type="Script" path="res://addons/editor_proximity_streaming/proximity_placement_3d.gd" id="1"]\n\n'
        '[node name="Room" type="Node3D"]\nmetadata/stream_volume = AABB(-2, 0, 2, 4, 3, 3)\n\n'
        '[node name="Detail" type="Node3D" parent="." groups=["interior_detail"]]\n'
        'position = Vector3(0, 1, 3)\nscript = ExtResource("1")\n'
        'scene_path = "res://detail.tscn"\nstream_class = &"dist_near"\n'
    )
    (project / "proximity_prefabs.json").write_text(json.dumps(
        {"res://class_near.tscn": {"class": "dist_near", "groups": ["world_object"]}}
    ))


def main():
    evidence = Path(tempfile.mkdtemp(prefix="editor-proximity-streaming-test-"))
    project = evidence / "project"
    create_fixture(project)
    create_class_fixture(project)
    log_path = evidence / "editor.log"
    print(f"Evidências em {evidence}", flush=True)
    environment = os.environ | {
        "XDG_DATA_HOME": str(evidence / "data"),
        "XDG_CONFIG_HOME": str(evidence / "config"),
        "XDG_CACHE_HOME": str(evidence / "cache"),
    }
    command = [
        os.environ.get("GODOT_BIN", "godot"),
        "--editor", "--path", str(project), "--rendering-method", "gl_compatibility",
        "--resolution", "1100x680", "res://world.tscn",
    ]
    try:
        with log_path.open("w", encoding="utf-8") as log:
            result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=65)
    except subprocess.TimeoutExpired:
        print(f"O editor excedeu o tempo do teste. Consulte {log_path}.")
        return 1

    output = log_path.read_text(encoding="utf-8", errors="replace")
    for line in output.splitlines():
        if line.startswith(("Godot Engine", "PASS ", "ERROR:", "SCRIPT ERROR:")):
            print(line)
    if result.returncode != 0 or "PASS editor_proximity_streaming" not in output:
        print(f"O teste falhou. Consulte {log_path}.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
