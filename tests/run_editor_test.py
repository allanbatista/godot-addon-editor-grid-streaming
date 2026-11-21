import os
from pathlib import Path
from shutil import copyfile, copytree
import subprocess
import tempfile

REPOSITORY = Path(__file__).resolve().parent.parent

PROJECT = '''config_version=5

[application]
config/name="Editor Proximity Streaming Test"

[editor_plugins]
enabled=PackedStringArray("res://addons/editor_proximity_streaming/plugin.cfg", "res://addons/test_probe/plugin.cfg")

[rendering]
renderer/rendering_method="gl_compatibility"
'''

PREFAB = '''[gd_scene format=3]

[sub_resource type="BoxMesh" id="box"]
size = Vector3(2, 2, 2)

[node name="Prefab" type="Node3D"]

[node name="Building" type="MeshInstance3D" parent="."]
mesh = SubResource("box")
'''

WORLD = '''[gd_scene format=3]

[ext_resource type="PackedScene" path="res://prefab.tscn" id="prefab"]

[node name="World" type="Node3D"]

[node name="Nearby" parent="." instance_placeholder="res://nearby.tscn"]
position = Vector3(2, 0, 0)

[node name="NearBox" parent="." groups=["dist_near"] instance_placeholder="res://prefab.tscn"]
position = Vector3(-9, 0, 0)

[node name="NearBoxTwin" parent="." instance_placeholder="res://prefab.tscn"]
position = Vector3(9, 0, 0)
metadata/stream_class = "dist_near"

[node name="LocalBox" parent="." groups=["dist_local"] instance_placeholder="res://prefab.tscn"]
position = Vector3(40, 0, 0)

[node name="Room" parent="." groups=["dist_near"] instance_placeholder="res://room.tscn"]
position = Vector3(14, 0, 0)

[node name="Untagged" parent="." instance_placeholder="res://prefab.tscn"]
position = Vector3(150, 0, 0)

[node name="Regular" parent="." groups=["dist_near"] instance=ExtResource("prefab")]
position = Vector3(150, 0, 0)
'''


def create_fixture(project):
    addon = "editor_proximity_streaming"
    copytree(REPOSITORY / "addons" / addon, project / "addons" / addon)
    probe = project / "addons" / "test_probe"
    probe.mkdir()
    (probe / "plugin.cfg").write_text('[plugin]\nname="Test Probe"\nscript="editor_test.gd"\n')
    copyfile(REPOSITORY / "tests" / "editor_test.gd", probe / "editor_test.gd")
    (project / "project.godot").write_text(PROJECT)
    (project / "world.tscn").write_text(WORLD)
    (project / "prefab.tscn").write_text(PREFAB)
    (project / "nearby.tscn").write_text(PREFAB.replace(
        '[node name="Prefab" type="Node3D"]',
        '[node name="Prefab" type="Node3D"]\nmetadata/stream_class = "dist_near"',
    ))
    (project / "room.tscn").write_text(PREFAB + '''
[node name="Interior" parent="." groups=["dist_near"] instance_placeholder="res://prefab.tscn"]
''')


def main():
    evidence = Path(tempfile.mkdtemp(prefix="editor-proximity-streaming-test-"))
    project = evidence / "project"
    create_fixture(project)
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
