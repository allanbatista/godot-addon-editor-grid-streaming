import os
from pathlib import Path
from shutil import copytree, copyfile
import subprocess
import tempfile

REPOSITORY = Path(__file__).resolve().parent.parent

PROJECT = """config_version=5

[application]
config/name="Editor Grid Streaming Test"

[editor_plugins]
enabled=PackedStringArray("res://addons/editor_grid_streaming/plugin.cfg", "res://addons/test_probe/plugin.cfg")

[rendering]
renderer/rendering_method="gl_compatibility"
"""

WORLD = """[gd_scene format=3]

[ext_resource type="Script" path="res://addons/editor_grid_streaming/editor_streaming_grid_3d.gd" id="1"]

[node name="World" type="Node3D"]

[node name="Grid" type="Node3D" parent="."]
position = Vector3(100, 0, -40)
script = ExtResource("1")
cells_directory = "res://cells"
cell_size = 10.0
"""

CELL = """[gd_scene format=3]

[sub_resource type="BoxMesh" id="BoxMesh_1"]
size = Vector3(7, 2, 7)

[node name="Cell" type="Node3D"]

[node name="Building" type="MeshInstance3D" parent="."]
position = Vector3(5, 1, 5)
mesh = SubResource("BoxMesh_1")
"""


def create_fixture(project):
    copytree(REPOSITORY / "addons" / "editor_grid_streaming", project / "addons" / "editor_grid_streaming")
    probe = project / "addons" / "test_probe"
    probe.mkdir()
    (probe / "plugin.cfg").write_text('[plugin]\nname="Test Probe"\nscript="editor_test.gd"\n')
    copyfile(REPOSITORY / "tests" / "editor_test.gd", probe / "editor_test.gd")

    (project / "project.godot").write_text(PROJECT)
    (project / "world.tscn").write_text(WORLD)
    cells = project / "cells"
    cells.mkdir()
    for x in range(-3, 4):
        for z in range(-3, 4):
            if (x, z) != (3, 3):
                (cells / f"cell_{x}_{z}.tscn").write_text(CELL)


def main():
    evidence = Path(tempfile.mkdtemp(prefix="editor-grid-streaming-test-"))
    project = evidence / "project"
    create_fixture(project)
    log_path = evidence / "editor.log"
    print(f"Evidências em {evidence}", flush=True)
    environment = os.environ | {
        "XDG_DATA_HOME": str(evidence / "data"),
        "XDG_CONFIG_HOME": str(evidence / "config"),
        "XDG_CACHE_HOME": str(evidence / "cache"),
        "GRID_TEST_OUTPUT": str(evidence),
    }
    command = [
        os.environ.get("GODOT_BIN", "godot"),
        "--editor", "--path", str(project), "--rendering-method", "gl_compatibility",
        "--resolution", "1280x720", "res://world.tscn",
    ]
    try:
        with log_path.open("w", encoding="utf-8") as log:
            result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=75)
    except subprocess.TimeoutExpired:
        print(f"O editor excedeu o tempo do teste. Consulte {log_path}.")
        return 1

    output = log_path.read_text(encoding="utf-8", errors="replace")
    for line in output.splitlines():
        if line.startswith(("Godot Engine", "PASS ", "ERROR:", "SCRIPT ERROR:")):
            print(line)
    if result.returncode != 0 or "PASS editor_grid_streaming" not in output:
        print(f"O teste falhou. Consulte {log_path}.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
