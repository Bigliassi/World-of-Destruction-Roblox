#!/usr/bin/env python3
"""
build_rbxlx.py
Discovers all .luau scripts under Roblox/src/ and builds a complete, valid
Roblox XML place file at Roblox/WorldOfDestruction.rbxlx.
"""

from __future__ import annotations
import html
from pathlib import Path
from typing import List, Tuple

ROOT_DIR = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT_DIR / "src"
OUTPUT_FILE = ROOT_DIR / "WorldOfDestruction.rbxlx"


class RefGen:
    def __init__(self) -> None:
        self._counter = 0

    def next(self) -> str:
        self._counter += 1
        return f"RBX{self._counter:08X}"


def xml_escape(text: str) -> str:
    return html.escape(text, quote=True)


def cdata_wrap(code: str) -> str:
    safe = code.replace("]]>", "]]]]><![CDATA[>")
    return f"<![CDATA[{safe}]]>"


def clean_script_name(path: Path) -> str:
    name = path.name
    for suffix in (".server.luau", ".script.luau", ".client.luau", ".module.luau", ".luau", ".lua"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return path.stem


def make_script_item(ref: RefGen, class_name: str, name: str, source: str, indent: int = 2) -> str:
    pad = "\t" * indent
    return (
        f'{pad}<Item class="{class_name}" referent="{ref.next()}">\n'
        f"{pad}\t<Properties>\n"
        f'{pad}\t\t<bool name="Disabled">false</bool>\n'
        f'{pad}\t\t<string name="Name">{xml_escape(name)}</string>\n'
        f'{pad}\t\t<ProtectedString name="Source">{cdata_wrap(source)}</ProtectedString>\n'
        f"{pad}\t</Properties>\n"
        f"{pad}</Item>"
    )


def make_folder_item(ref: RefGen, name: str, children_xml: List[str], indent: int = 2) -> str:
    pad = "\t" * indent
    inner = "\n".join(children_xml)
    if inner:
        inner = "\n" + inner + "\n"
    else:
        inner = "\n"
    return (
        f'{pad}<Item class="Folder" referent="{ref.next()}">\n'
        f"{pad}\t<Properties>\n"
        f'{pad}\t\t<string name="Name">{xml_escape(name)}</string>\n'
        f"{pad}\t</Properties>{inner}"
        f"{pad}</Item>"
    )


def discover_scripts(subdir: Path, default_class: str) -> List[Tuple[str, str, Path]]:
    if not subdir.exists():
        return []
    found: List[Tuple[str, str, Path]] = []
    for path in sorted(subdir.rglob("*.luau")):
        if path.name.endswith(".server.luau"):
            cls = "Script"
        elif path.name.endswith(".client.luau"):
            cls = "LocalScript"
        elif path.name.endswith(".module.luau"):
            cls = "ModuleScript"
        else:
            cls = default_class
        found.append((cls, clean_script_name(path), path))
    return found


def build_workspace_xml(ref: RefGen) -> str:
    return f"""\t<Item class="Workspace" referent="{ref.next()}">
\t\t<Properties>
\t\t\t<string name="Name">Workspace</string>
\t\t\t<float name="Gravity">196.2</float>
\t\t\t<token name="StreamingEnabled">1</token>
\t\t</Properties>
\t\t<Item class="Camera" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Camera</string>
\t\t\t\t<float name="FieldOfView">70</float>
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="Terrain" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Terrain</string>
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="SpawnLocation" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">SpawnLocation</string>
\t\t\t\t<bool name="Anchored">true</bool>
\t\t\t\t<bool name="CanCollide">true</bool>
\t\t\t\t<bool name="Neutral">true</bool>
\t\t\t\t<float name="Transparency">0</float>
\t\t\t\t<Vector3 name="size">
\t\t\t\t\t<X>12</X>
\t\t\t\t\t<Y>1</Y>
\t\t\t\t\t<Z>12</Z>
\t\t\t\t</Vector3>
\t\t\t\t<CoordinateFrame name="CFrame">
\t\t\t\t\t<X>0</X>
\t\t\t\t\t<Y>2</Y>
\t\t\t\t\t<Z>0</Z>
\t\t\t\t\t<R00>1</R00><R01>0</R01><R02>0</R02>
\t\t\t\t\t<R10>0</R10><R11>1</R11><R12>0</R12>
\t\t\t\t\t<R20>0</R20><R21>0</R21><R22>1</R22>
\t\t\t\t</CoordinateFrame>
\t\t\t</Properties>
\t\t</Item>
\t</Item>"""


def build_lighting_xml(ref: RefGen) -> str:
    return f"""\t<Item class="Lighting" referent="{ref.next()}">
\t\t<Properties>
\t\t\t<string name="Name">Lighting</string>
\t\t\t<float name="Brightness">2.5</float>
\t\t\t<float name="ClockTime">15.5</float>
\t\t\t<float name="GeographicLatitude">34</float>
\t\t\t<bool name="GlobalShadows">true</bool>
\t\t\t<Color3 name="Ambient"><R>0.22</R><G>0.24</G><B>0.28</B></Color3>
\t\t\t<Color3 name="OutdoorAmbient"><R>0.42</R><G>0.45</G><B>0.52</B></Color3>
\t\t</Properties>
\t\t<Item class="Atmosphere" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Atmosphere</string>
\t\t\t\t<float name="Density">0.32</float>
\t\t\t\t<float name="Offset">0.15</float>
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="BloomEffect" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Bloom</string>
\t\t\t\t<bool name="Enabled">true</bool>
\t\t\t\t<float name="Intensity">0.4</float>
\t\t\t\t<float name="Size">24</float>
\t\t\t\t<float name="Threshold">0.95</float>
\t\t\t</Properties>
\t\t</Item>
\t</Item>"""


def build_place_xml() -> Tuple[str, List[Tuple[str, str, Path]]]:
    ref = RefGen()
    manifest: List[Tuple[str, str, Path]] = []

    # 1. ReplicatedStorage -> Shared (ModuleScripts) + Remotes folder
    shared_items: List[str] = []
    rep_dir = SRC_DIR / "ReplicatedStorage"
    shared_dir = rep_dir / "Shared"
    target_shared = shared_dir if shared_dir.exists() else rep_dir
    for cls, name, path in discover_scripts(target_shared, "ModuleScript"):
        code = path.read_text(encoding="utf-8")
        shared_items.append(make_script_item(ref, "ModuleScript", name, code, indent=3))
        manifest.append(("ReplicatedStorage.Shared", name, path))

    shared_folder_xml = make_folder_item(ref, "Shared", shared_items, indent=2)
    remotes_folder_xml = make_folder_item(ref, "Remotes", [], indent=2)
    replicated_storage_xml = (
        f'\t<Item class="ReplicatedStorage" referent="{ref.next()}">\n'
        f"\t\t<Properties>\n"
        f'\t\t\t<string name="Name">ReplicatedStorage</string>\n'
        f"\t\t</Properties>\n"
        f"{shared_folder_xml}\n"
        f"{remotes_folder_xml}\n"
        f"\t</Item>"
    )

    # 2. ServerScriptService -> Scripts
    server_items: List[str] = []
    for cls, name, path in discover_scripts(SRC_DIR / "ServerScriptService", "Script"):
        code = path.read_text(encoding="utf-8")
        server_items.append(make_script_item(ref, cls, name, code, indent=2))
        manifest.append(("ServerScriptService", name, path))

    server_inner = "\n" + "\n".join(server_items) + "\n" if server_items else "\n"
    server_script_service_xml = (
        f'\t<Item class="ServerScriptService" referent="{ref.next()}">\n'
        f"\t\t<Properties>\n"
        f'\t\t\t<string name="Name">ServerScriptService</string>\n'
        f"\t\t</Properties>{server_inner}"
        f"\t</Item>"
    )

    # 3. StarterGui -> LocalScripts
    gui_items: List[str] = []
    for cls, name, path in discover_scripts(SRC_DIR / "StarterGui", "LocalScript"):
        code = path.read_text(encoding="utf-8")
        gui_items.append(make_script_item(ref, cls, name, code, indent=2))
        manifest.append(("StarterGui", name, path))

    gui_inner = "\n" + "\n".join(gui_items) + "\n" if gui_items else "\n"
    starter_gui_xml = (
        f'\t<Item class="StarterGui" referent="{ref.next()}">\n'
        f"\t\t<Properties>\n"
        f'\t\t\t<string name="Name">StarterGui</string>\n'
        f'\t\t\t<bool name="ResetPlayerGuiOnSpawn">false</bool>\n'
        f"\t\t</Properties>{gui_inner}"
        f"\t</Item>"
    )

    # 4. StarterPlayer -> StarterPlayerScripts & StarterCharacterScripts
    sps_items: List[str] = []
    sps_dir = SRC_DIR / "StarterPlayer" / "StarterPlayerScripts"
    for cls, name, path in discover_scripts(sps_dir, "LocalScript"):
        code = path.read_text(encoding="utf-8")
        sps_items.append(make_script_item(ref, cls, name, code, indent=3))
        manifest.append(("StarterPlayer.StarterPlayerScripts", name, path))

    scs_items: List[str] = []
    scs_dir = SRC_DIR / "StarterPlayer" / "StarterCharacterScripts"
    for cls, name, path in discover_scripts(scs_dir, "LocalScript"):
        code = path.read_text(encoding="utf-8")
        scs_items.append(make_script_item(ref, cls, name, code, indent=3))
        manifest.append(("StarterPlayer.StarterCharacterScripts", name, path))

    sps_inner = "\n" + "\n".join(sps_items) + "\n" if sps_items else "\n"
    scs_inner = "\n" + "\n".join(scs_items) + "\n" if scs_items else "\n"

    starter_player_xml = (
        f'\t<Item class="StarterPlayer" referent="{ref.next()}">\n'
        f"\t\t<Properties>\n"
        f'\t\t\t<string name="Name">StarterPlayer</string>\n'
        f"\t\t</Properties>\n"
        f'\t\t<Item class="StarterPlayerScripts" referent="{ref.next()}">\n'
        f"\t\t\t<Properties>\n"
        f'\t\t\t\t<string name="Name">StarterPlayerScripts</string>\n'
        f"\t\t\t</Properties>{sps_inner}"
        f"\t\t</Item>\n"
        f'\t\t<Item class="StarterCharacterScripts" referent="{ref.next()}">\n'
        f"\t\t\t<Properties>\n"
        f'\t\t\t\t<string name="Name">StarterCharacterScripts</string>\n'
        f"\t\t\t</Properties>{scs_inner}"
        f"\t\t</Item>\n"
        f"\t</Item>"
    )

    services_xml = [
        build_workspace_xml(ref),
        f'\t<Item class="Players" referent="{ref.next()}"><Properties><string name="Name">Players</string></Properties></Item>',
        build_lighting_xml(ref),
        replicated_storage_xml,
        server_script_service_xml,
        starter_gui_xml,
        starter_player_xml,
        f'\t<Item class="SoundService" referent="{ref.next()}"><Properties><string name="Name">SoundService</string></Properties></Item>',
    ]

    full_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        "\t<External>null</External>\n"
        "\t<External>nil</External>\n"
        + "\n".join(services_xml)
        + "\n</roblox>\n"
    )
    return full_xml, manifest


def main() -> None:
    xml_content, manifest = build_place_xml()
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(xml_content, encoding="utf-8")

    print(f"Built Roblox XML place: {OUTPUT_FILE}")
    print(f"Packed {len(manifest)} Luau scripts:")
    for container, name, path in manifest:
        rel = path.relative_to(ROOT_DIR)
        print(f"  - [{container}] {name}  ({rel})")
    print(f"Total file size: {OUTPUT_FILE.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
