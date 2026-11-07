#!/usr/bin/env python3
"""
build_rbxlx.py
Discovers all .luau scripts under Roblox/src/, pre-bakes a rich 3D LeoCity_EditPreview
inside Workspace (with Workspace.Camera positioned at (0, 45, 85) looking toward (0, 10, 0)),
and builds a complete, valid Roblox XML place file at Roblox/WorldOfDestruction.rbxlx.
"""

from __future__ import annotations
import html
import math
from pathlib import Path
from typing import List, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT_DIR / "src"
OUTPUT_FILE = ROOT_DIR / "WorldOfDestruction.rbxlx"

# Roblox Enum.Material numeric token values
MAT_PLASTIC = 256
MAT_SMOOTH_PLASTIC = 272
MAT_NEON = 288
MAT_WOOD = 512
MAT_WOOD_PLANKS = 528
MAT_MARBLE = 784
MAT_CONCRETE = 816
MAT_CORRODED_METAL = 1040
MAT_METAL = 1088
MAT_GRASS = 1280
MAT_SAND = 1296
MAT_ASPHALT = 1376
MAT_GLASS = 1568

# Roblox Enum.NormalId numeric token values
FACE_BACK = 2
FACE_FRONT = 5


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


def color_xml(r: int, g: int, b: int, indent: int) -> str:
    pad = "\t" * indent
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    uint_val = 0xFF000000 | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF)
    return (
        f'{pad}<Color3 name="Color"><R>{rf:.4f}</R><G>{gf:.4f}</G><B>{bf:.4f}</B></Color3>\n'
        f'{pad}<Color3uint8 name="Color3uint8">{uint_val}</Color3uint8>'
    )


def cframe_yaw_xml(x: float, y: float, z: float, yaw_deg: float = 0.0, indent: int = 4, name: str = "CFrame") -> str:
    pad = "\t" * indent
    rad = math.radians(yaw_deg)
    c = math.cos(rad)
    s = math.sin(rad)
    return (
        f'{pad}<CoordinateFrame name="{name}">\n'
        f"{pad}\t<X>{x:.3f}</X><Y>{y:.3f}</Y><Z>{z:.3f}</Z>\n"
        f"{pad}\t<R00>{c:.6f}</R00><R01>0</R01><R02>{s:.6f}</R02>\n"
        f"{pad}\t<R10>0</R10><R11>1</R11><R12>0</R12>\n"
        f"{pad}\t<R20>{-s:.6f}</R20><R21>0</R21><R22>{c:.6f}</R22>\n"
        f"{pad}</CoordinateFrame>"
    )


def cframe_look_at_xml(
    eye: Tuple[float, float, float],
    target: Tuple[float, float, float],
    indent: int = 4,
    name: str = "CFrame",
) -> str:
    pad = "\t" * indent
    ex, ey, ez = eye
    tx, ty, tz = target
    # Back vector = (eye - target).Unit
    bx, by, bz = ex - tx, ey - ty, ez - tz
    blen = math.sqrt(bx * bx + by * by + bz * bz) or 1.0
    bx, by, bz = bx / blen, by / blen, bz / blen

    # Right vector = Up(0,1,0) x Back
    rx, ry, rz = bz, 0.0, -bx
    rlen = math.sqrt(rx * rx + ry * ry + rz * rz) or 1.0
    rx, ry, rz = rx / rlen, ry / rlen, rz / rlen

    # True Up vector = Back x Right
    ux = by * rz - bz * ry
    uy = bz * rx - bx * rz
    uz = bx * ry - by * rx

    return (
        f'{pad}<CoordinateFrame name="{name}">\n'
        f"{pad}\t<X>{ex:.3f}</X><Y>{ey:.3f}</Y><Z>{ez:.3f}</Z>\n"
        f"{pad}\t<R00>{rx:.6f}</R00><R01>{ux:.6f}</R01><R02>{bx:.6f}</R02>\n"
        f"{pad}\t<R10>{ry:.6f}</R10><R11>{uy:.6f}</R11><R12>{by:.6f}</R12>\n"
        f"{pad}\t<R20>{rz:.6f}</R20><R21>{uz:.6f}</R21><R22>{bz:.6f}</R22>\n"
        f"{pad}</CoordinateFrame>"
    )


def rotate_offset(
    origin: Tuple[float, float, float],
    yaw_deg: float,
    local_offset: Tuple[float, float, float],
) -> Tuple[float, float, float]:
    rad = math.radians(yaw_deg)
    c = math.cos(rad)
    s = math.sin(rad)
    lx, ly, lz = local_offset
    wx = origin[0] + lx * c + lz * s
    wy = origin[1] + ly
    wz = origin[2] - lx * s + lz * c
    return (wx, wy, wz)


def make_surface_sign_xml(
    ref: RefGen,
    text: str,
    text_rgb: Tuple[int, int, int],
    face: int = FACE_FRONT,
    indent: int = 4,
) -> str:
    pad = "\t" * indent
    tr, tg, tb = text_rgb[0] / 255.0, text_rgb[1] / 255.0, text_rgb[2] / 255.0
    return (
        f'{pad}<Item class="SurfaceGui" referent="{ref.next()}">\n'
        f"{pad}\t<Properties>\n"
        f'{pad}\t\t<string name="Name">SignGui</string>\n'
        f'{pad}\t\t<token name="Face">{face}</token>\n'
        f'{pad}\t\t<token name="SizingMode">1</token>\n'
        f'{pad}\t\t<float name="PixelsPerStud">24</float>\n'
        f'{pad}\t\t<float name="LightInfluence">0</float>\n'
        f"{pad}\t</Properties>\n"
        f'{pad}\t<Item class="TextLabel" referent="{ref.next()}">\n'
        f"{pad}\t\t<Properties>\n"
        f'{pad}\t\t\t<string name="Name">SignLabel</string>\n'
        f'{pad}\t\t\t<UDim2 name="Size"><XS>1</XS><XO>0</XO><YS>1</YS><YO>0</YO></UDim2>\n'
        f'{pad}\t\t\t<float name="BackgroundTransparency">1</float>\n'
        f'{pad}\t\t\t<string name="Text">{xml_escape(text)}</string>\n'
        f'{pad}\t\t\t<Color3 name="TextColor3"><R>{tr:.4f}</R><G>{tg:.4f}</G><B>{tb:.4f}</B></Color3>\n'
        f'{pad}\t\t\t<bool name="TextScaled">true</bool>\n'
        f'{pad}\t\t\t<token name="Font">18</token>\n'
        f'{pad}\t\t\t<float name="TextStrokeTransparency">0.2</float>\n'
        f"{pad}\t\t</Properties>\n"
        f"{pad}\t</Item>\n"
        f"{pad}</Item>"
    )


def make_part_xml(
    ref: RefGen,
    name: str,
    size: Tuple[float, float, float],
    pos: Tuple[float, float, float],
    rgb: Tuple[int, int, int],
    material: int = MAT_CONCRETE,
    yaw_deg: float = 0.0,
    transparency: float = 0.0,
    can_collide: bool = True,
    class_name: str = "Part",
    children_xml: Optional[List[str]] = None,
    indent: int = 4,
) -> str:
    pad = "\t" * indent
    sx, sy, sz = size
    px, py, pz = pos
    r, g, b = rgb
    inner = ""
    if children_xml:
        inner = "\n" + "\n".join(children_xml) + "\n" + pad
    else:
        inner = "\n" + pad
    shape_line = f'{pad}\t\t<token name="shape">1</token>\n' if class_name == "Part" else ""
    return (
        f'{pad}<Item class="{class_name}" referent="{ref.next()}">\n'
        f"{pad}\t<Properties>\n"
        f'{pad}\t\t<string name="Name">{xml_escape(name)}</string>\n'
        f'{pad}\t\t<bool name="Anchored">true</bool>\n'
        f'{pad}\t\t<bool name="CanCollide">{"true" if can_collide else "false"}</bool>\n'
        f'{pad}\t\t<float name="Transparency">{transparency:.2f}</float>\n'
        f'{pad}\t\t<token name="Material">{material}</token>\n'
        f'{pad}\t\t<token name="TopSurface">0</token>\n'
        f'{pad}\t\t<token name="BottomSurface">0</token>\n'
        f"{shape_line}"
        f'{pad}\t\t<Vector3 name="size"><X>{sx:.2f}</X><Y>{sy:.2f}</Y><Z>{sz:.2f}</Z></Vector3>\n'
        f"{color_xml(r, g, b, indent + 2)}\n"
        f"{cframe_yaw_xml(px, py, pz, yaw_deg, indent + 2)}\n"
        f"{pad}\t</Properties>{inner}"
        f"</Item>"
    )


def make_model_xml(ref: RefGen, name: str, children_xml: List[str], indent: int = 3) -> str:
    pad = "\t" * indent
    inner = "\n" + "\n".join(children_xml) + "\n" if children_xml else "\n"
    return (
        f'{pad}<Item class="Model" referent="{ref.next()}">\n'
        f"{pad}\t<Properties>\n"
        f'{pad}\t\t<string name="Name">{xml_escape(name)}</string>\n'
        f"{pad}\t</Properties>{inner}"
        f"{pad}</Item>"
    )


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


def build_stunt_ramp_preview(
    ref: RefGen,
    pos: Tuple[float, float, float],
    yaw_deg: float,
    width: float,
    height: float,
    length: float,
    label_text: str,
    indent: int = 4,
) -> str:
    ramp_width = max(width, 26.0)
    total_len = max(length, 32.0)
    len1 = total_len * 0.36
    len2 = total_len * 0.34
    len3 = total_len * 0.30
    h1 = len1 * math.tan(math.radians(10.0))
    h2 = len2 * math.tan(math.radians(17.0))
    h3 = len3 * math.tan(math.radians(23.0))
    y0 = -0.2
    y1 = y0 + h1
    y2 = y1 + h2
    y3 = y2 + h3
    z_start = total_len * 0.5
    z1_center = z_start - len1 * 0.5
    z1_end = z_start - len1
    z2_center = z1_end - len2 * 0.5
    z2_end = z1_end - len2
    z3_center = z2_end - len3 * 0.5

    parts: List[str] = []
    parts.append(
        make_part_xml(
            ref,
            "RampWedge",
            (ramp_width, h1, len1),
            rotate_offset(pos, yaw_deg, (0.0, y0 + h1 * 0.5, z1_center)),
            (132, 138, 152),
            MAT_CONCRETE,
            yaw_deg,
            class_name="WedgePart",
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "MidSupportBase",
            (ramp_width, max(0.2, y1), len2 - 0.1),
            rotate_offset(pos, yaw_deg, (0.0, y1 * 0.5, z2_center - 0.05)),
            (118, 125, 140),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "MidRampWedge",
            (ramp_width, h2, len2),
            rotate_offset(pos, yaw_deg, (0.0, y1 + h2 * 0.5, z2_center)),
            (118, 125, 140),
            MAT_CONCRETE,
            yaw_deg,
            class_name="WedgePart",
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "LipSupportBase",
            (ramp_width, max(0.2, y2), len3 - 0.1),
            rotate_offset(pos, yaw_deg, (0.0, y2 * 0.5, z3_center - 0.05)),
            (106, 114, 130),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "LaunchLipWedge",
            (ramp_width, h3, len3),
            rotate_offset(pos, yaw_deg, (0.0, y2 + h3 * 0.5, z3_center)),
            (106, 114, 130),
            MAT_CONCRETE,
            yaw_deg,
            class_name="WedgePart",
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "LeftRail",
            (0.8, y3 + 0.8, total_len),
            rotate_offset(pos, yaw_deg, (-ramp_width * 0.5 + 0.4, y3 * 0.5, 0.0)),
            (255, 155, 25),
            MAT_NEON,
            yaw_deg,
            can_collide=False,
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "RightRail",
            (0.8, y3 + 0.8, total_len),
            rotate_offset(pos, yaw_deg, (ramp_width * 0.5 - 0.4, y3 * 0.5, 0.0)),
            (255, 155, 25),
            MAT_NEON,
            yaw_deg,
            can_collide=False,
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "JumpLipGlow",
            (ramp_width, 1.2, 3.0),
            rotate_offset(pos, yaw_deg, (0.0, y3 + 0.6, -total_len * 0.5 + 1.5)),
            (255, 220, 40),
            MAT_NEON,
            yaw_deg,
            transparency=0.35,
            can_collide=False,
            indent=indent + 1,
        )
    )
    return make_model_xml(ref, label_text, parts, indent=indent)


def build_speed_shop_preview(
    ref: RefGen,
    pos: Tuple[float, float, float],
    yaw_deg: float,
    name: str = "SpeedShop",
    indent: int = 4,
) -> str:
    parts: List[str] = [
        make_part_xml(
            ref,
            "ShowroomFloor",
            (54.0, 0.8, 44.0),
            rotate_offset(pos, yaw_deg, (0.0, 0.4, 0.0)),
            (28, 32, 42),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "BackWall",
            (52.0, 22.0, 2.0),
            rotate_offset(pos, yaw_deg, (0.0, 11.0, 16.0)),
            (22, 26, 36),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "LeftWall",
            (2.0, 22.0, 30.0),
            rotate_offset(pos, yaw_deg, (-25.0, 11.0, 2.0)),
            (22, 26, 36),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "RightWall",
            (2.0, 22.0, 30.0),
            rotate_offset(pos, yaw_deg, (25.0, 11.0, 2.0)),
            (22, 26, 36),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "Roof",
            (54.0, 1.6, 34.0),
            rotate_offset(pos, yaw_deg, (0.0, 22.5, 2.0)),
            (18, 20, 28),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "ShowroomGlass",
            (46.0, 16.0, 0.6),
            rotate_offset(pos, yaw_deg, (0.0, 8.5, -12.0)),
            (60, 210, 255),
            MAT_GLASS,
            yaw_deg,
            transparency=0.55,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "SignBoard",
            (38.0, 6.5, 1.5),
            rotate_offset(pos, yaw_deg, (0.0, 26.5, -11.0)),
            (16, 20, 30),
            MAT_METAL,
            yaw_deg,
            children_xml=[
                make_surface_sign_xml(ref, "LEO SPEED SHOP & DEALER", (40, 240, 255), FACE_FRONT, indent + 2),
                make_surface_sign_xml(ref, "LEO SPEED SHOP & DEALER", (40, 240, 255), FACE_BACK, indent + 2),
            ],
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "SpeedShopPad",
            (20.0, 0.6, 16.0),
            rotate_offset(pos, yaw_deg, (0.0, 0.4, -22.0)),
            (25, 235, 255),
            MAT_NEON,
            yaw_deg,
            can_collide=False,
            indent=indent + 1,
        ),
    ]
    return make_model_xml(ref, name, parts, indent=indent)


def build_mechanic_bay_preview(
    ref: RefGen,
    pos: Tuple[float, float, float],
    yaw_deg: float,
    name: str = "MechanicRepairBay",
    indent: int = 4,
) -> str:
    parts: List[str] = [
        make_part_xml(
            ref,
            "BayFloor",
            (36.0, 0.8, 36.0),
            rotate_offset(pos, yaw_deg, (0.0, 0.4, 0.0)),
            (34, 38, 46),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "LeftWall",
            (2.0, 16.0, 28.0),
            rotate_offset(pos, yaw_deg, (-14.0, 8.0, 0.0)),
            (48, 52, 62),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "RightWall",
            (2.0, 16.0, 28.0),
            rotate_offset(pos, yaw_deg, (14.0, 8.0, 0.0)),
            (48, 52, 62),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "Roof",
            (32.0, 1.5, 30.0),
            rotate_offset(pos, yaw_deg, (0.0, 16.5, 0.0)),
            (28, 32, 40),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "MechanicSign",
            (28.0, 5.0, 1.4),
            rotate_offset(pos, yaw_deg, (0.0, 19.8, -13.0)),
            (20, 26, 32),
            MAT_METAL,
            yaw_deg,
            children_xml=[
                make_surface_sign_xml(ref, "INSTANT REPAIR & NITRO REFILL", (60, 255, 120), FACE_FRONT, indent + 2),
                make_surface_sign_xml(ref, "INSTANT REPAIR & NITRO REFILL", (60, 255, 120), FACE_BACK, indent + 2),
            ],
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "RepairPad",
            (20.0, 0.6, 22.0),
            rotate_offset(pos, yaw_deg, (0.0, 0.5, 0.0)),
            (50, 255, 110),
            MAT_NEON,
            yaw_deg,
            transparency=0.25,
            can_collide=False,
            indent=indent + 1,
        ),
    ]
    return make_model_xml(ref, name, parts, indent=indent)


def build_skyscraper_preview(
    ref: RefGen,
    center: Tuple[float, float, float],
    width: float,
    depth: float,
    height: float,
    tint: Tuple[int, int, int],
    name: str,
    is_leo_tower: bool = False,
    indent: int = 4,
) -> str:
    cx, cy, cz = center
    parts: List[str] = [
        make_part_xml(
            ref,
            "Shaft",
            (width, height, depth),
            (cx, cy + height * 0.5, cz),
            tint,
            MAT_CONCRETE,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "GlassLobby",
            (width * 0.82, 14.0, depth + 0.6),
            (cx, cy + 7.0, cz),
            (110, 200, 255),
            MAT_GLASS,
            transparency=0.45,
            indent=indent + 1,
        ),
    ]

    floors = max(3, min(10, int(height // 16)))
    for f in range(1, floors + 1):
        y = cy + 16.0 + (f - 0.5) * ((height - 20.0) / floors)
        win_col = (255, 215, 135) if (f % 2 == 0) else (120, 195, 255)
        parts.append(
            make_part_xml(
                ref,
                "WindowBandZ",
                (width * 0.86, 3.2, depth + 0.4),
                (cx, y, cz),
                win_col,
                MAT_NEON,
                indent=indent + 1,
            )
        )
        parts.append(
            make_part_xml(
                ref,
                "WindowBandX",
                (width + 0.4, 3.2, depth * 0.86),
                (cx, y, cz),
                win_col,
                MAT_NEON,
                indent=indent + 1,
            )
        )

    crown_h = height * 0.18
    crown_children: List[str] = []
    if is_leo_tower:
        crown_children = [
            make_surface_sign_xml(ref, "LEO TOWER", (255, 215, 60), FACE_FRONT, indent + 2),
            make_surface_sign_xml(ref, "LEO TOWER", (255, 215, 60), FACE_BACK, indent + 2),
        ]
    parts.append(
        make_part_xml(
            ref,
            "Crown",
            (width * 0.7, crown_h, depth * 0.7),
            (cx, cy + height + crown_h * 0.5, cz),
            tint,
            MAT_METAL,
            children_xml=crown_children,
            indent=indent + 1,
        )
    )

    if is_leo_tower:
        parts.append(
            make_part_xml(
                ref,
                "LeoSpire",
                (6.0, 28.0, 6.0),
                (cx, cy + height + crown_h + 14.0, cz),
                (255, 215, 55),
                MAT_NEON,
                can_collide=False,
                indent=indent + 1,
            )
        )

    return make_model_xml(ref, name, parts, indent=indent)


def build_leo_city_edit_preview_xml(ref: RefGen) -> str:
    """
    Builds Workspace.LeoCity_EditPreview so that opening WorldOfDestruction.rbxlx in Roblox Studio
    Edit Mode immediately displays the full 3D sunlit Leo City (9x9 blocks, 2,200x2,200 studs) in front
    of the viewport camera. Replaced cleanly at runtime by WorldBuilderService.script.luau when Play is pressed.
    """
    block_size = 200.0
    road_width = 42.0
    grid_radius = 4
    usable = block_size - road_width
    total_span = (grid_radius * 2 + 1) * block_size + 240.0
    grid_extent = (grid_radius + 1) * block_size

    ground_items: List[str] = [
        make_part_xml(
            ref,
            "CityBaseplate",
            (total_span, 4.0, total_span),
            (0.0, -2.0, 0.0),
            (138, 144, 155),
            MAT_CONCRETE,
            indent=4,
        ),
        make_part_xml(
            ref,
            "OceanWater",
            (380.0, 3.6, total_span),
            ((grid_radius + 1.2) * block_size, -1.6, 0.0),
            (38, 158, 238),
            MAT_GLASS,
            indent=4,
        ),
    ]

    roads_items: List[str] = []
    buildings_items: List[str] = []
    landmarks_items: List[str] = []
    zones_items: List[str] = []

    road_lines = [(i + 0.5) * block_size for i in range(-grid_radius - 1, grid_radius + 1)]
    roads_items.append(
        make_part_xml(
            ref,
            "GrandCentralAveNS",
            (road_width, 0.34, grid_extent * 2.0),
            (0.0, 0.17, 0.0),
            (62, 66, 76),
            MAT_ASPHALT,
            indent=4,
        )
    )
    for rx in road_lines:
        roads_items.append(
            make_part_xml(
                ref,
                "RoadNS",
                (road_width, 0.3, grid_extent * 2.0),
                (rx, 0.15, 0.0),
                (64, 68, 78),
                MAT_ASPHALT,
                indent=4,
            )
        )
        for z in range(int(-grid_extent + 20), int(grid_extent - 20) + 1, 56):
            roads_items.append(
                make_part_xml(
                    ref,
                    "LaneDashNS",
                    (0.8, 0.34, 14.0),
                    (rx, 0.17, float(z)),
                    (250, 210, 60),
                    MAT_SMOOTH_PLASTIC,
                    indent=4,
                )
            )

    for rz in road_lines:
        roads_items.append(
            make_part_xml(
                ref,
                "RoadEW",
                (grid_extent * 2.0, 0.32, road_width),
                (0.0, 0.16, rz),
                (64, 68, 78),
                MAT_ASPHALT,
                indent=4,
            )
        )
        for x in range(int(-grid_extent + 20), int(grid_extent - 20) + 1, 56):
            roads_items.append(
                make_part_xml(
                    ref,
                    "LaneDashEW",
                    (14.0, 0.35, 0.8),
                    (float(x), 0.175, rz),
                    (250, 210, 60),
                    MAT_SMOOTH_PLASTIC,
                    indent=4,
                )
            )

    # Crosswalks around the central Downtown & Leo Plaza intersections
    for rx in (-300.0, -100.0, 100.0, 300.0):
        for rz in (-300.0, -100.0, 100.0, 300.0):
            for s in (-2, -1, 1, 2):
                roads_items.append(
                    make_part_xml(
                        ref,
                        "CrosswalkN",
                        (3.2, 0.36, 1.2),
                        (rx + s * 5.5, 0.18, rz - road_width * 0.5 - 2.0),
                        (242, 245, 250),
                        MAT_SMOOTH_PLASTIC,
                        indent=4,
                    )
                )
                roads_items.append(
                    make_part_xml(
                        ref,
                        "CrosswalkE",
                        (1.2, 0.36, 3.2),
                        (rx + road_width * 0.5 + 2.0, 0.18, rz + s * 5.5),
                        (242, 245, 250),
                        MAT_SMOOTH_PLASTIC,
                        indent=4,
                    )
                )

    # City blocks, sidewalks, Leo Plaza fountain, Speed Shops, Mechanic Bays, Stunt Ramps, and Skyscrapers
    for bx in range(-grid_radius, grid_radius + 1):
        for bz in range(-grid_radius, grid_radius + 1):
            ox, oz = bx * block_size, bz * block_size
            if bx != 0:
                ground_items.append(
                    make_part_xml(
                        ref,
                        "SidewalkBlock",
                        (usable, 0.26, usable),
                        (ox, 0.13, oz),
                        (192, 188, 178),
                        MAT_CONCRETE,
                        indent=4,
                    )
                )
            else:
                side_w = (usable - road_width) * 0.5
                ground_items.append(
                    make_part_xml(
                        ref,
                        "SidewalkBlockW",
                        (side_w, 0.26, usable),
                        (ox - (road_width * 0.5 + side_w * 0.5), 0.13, oz),
                        (192, 188, 178),
                        MAT_CONCRETE,
                        indent=4,
                    )
                )
                ground_items.append(
                    make_part_xml(
                        ref,
                        "SidewalkBlockE",
                        (side_w, 0.26, usable),
                        (ox + (road_width * 0.5 + side_w * 0.5), 0.13, oz),
                        (192, 188, 178),
                        MAT_CONCRETE,
                        indent=4,
                    )
                )

            if bx == 0 and bz == 0:
                # Ornamental Marble Fountain in West Courtyard (-42, 0, 12) so Grand Central Ave stays wide open
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "LeoPlazaFountain",
                        (18.0, 3.2, 18.0),
                        (ox - 42.0, 1.8, oz + 12.0),
                        (215, 222, 232),
                        MAT_MARBLE,
                        indent=4,
                    )
                )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "FountainWaterTier",
                        (14.0, 1.4, 14.0),
                        (ox - 42.0, 3.6, oz + 12.0),
                        (65, 195, 245),
                        MAT_GLASS,
                        transparency=0.25,
                        indent=4,
                    )
                )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "FountainWaterSpire",
                        (2.8, 7.5, 2.8),
                        (ox - 42.0, 7.2, oz + 12.0),
                        (185, 235, 255),
                        MAT_MARBLE,
                        can_collide=False,
                        indent=4,
                    )
                )
                # Crate stacks & hydrants on Leo Plaza flanks
                for cx_off, cz_off in ((-28.0, -10.0), (28.0, -10.0)):
                    landmarks_items.append(
                        make_part_xml(
                            ref,
                            "PlazaCrateStack",
                            (6.4, 6.4, 3.2),
                            (ox + cx_off, 3.5, oz + cz_off),
                            (145, 98, 56),
                            MAT_WOOD_PLANKS,
                            indent=4,
                        )
                    )
                for hx in (-usable * 0.5 + 3.5, usable * 0.5 - 3.5):
                    landmarks_items.append(
                        make_part_xml(
                            ref,
                            "FireHydrant",
                            (1.6, 3.2, 1.6),
                            (ox + hx, 1.9, oz),
                            (220, 35, 35),
                            MAT_METAL,
                            indent=4,
                        )
                    )
                # Leo Plaza Stunt Mega-Ramp, Plaza Speed Shop & Plaza Mechanic Repair Bay
                zones_items.append(
                    build_stunt_ramp_preview(ref, (ox, 0.3, oz - 68.0), 0.0, 16.0, 7.5, 24.0, "LeoPlazaRamp", indent=4)
                )
                zones_items.append(
                    build_speed_shop_preview(ref, (ox + 54.0, 0.3, oz - 24.0), -90.0, "PlazaSpeedShop", indent=4)
                )
                zones_items.append(
                    build_mechanic_bay_preview(ref, (ox - 54.0, 0.3, oz - 24.0), 90.0, "PlazaMechanicRepairBay", indent=4)
                )
            elif bx == 1 and bz == 0:
                zones_items.append(build_speed_shop_preview(ref, (ox, 0.6, oz), -90.0, "SpeedShop", indent=4))
            elif bx == -1 and bz == 0:
                zones_items.append(build_mechanic_bay_preview(ref, (ox, 0.6, oz), 90.0, "MechanicRepairBay", indent=4))
            elif bx == 0 and bz == -2:
                zones_items.append(build_mechanic_bay_preview(ref, (ox, 0.6, oz), 0.0, "NorthMechanicRepairBay", indent=4))
                buildings_items.append(
                    make_part_xml(
                        ref,
                        "BoomGasStationCanopy",
                        (52.0, 2.2, 32.0),
                        (ox, 18.6, oz + 36.0),
                        (230, 45, 45),
                        MAT_METAL,
                        indent=4,
                    )
                )
            elif bx == 2 and bz == 2:
                zones_items.append(build_speed_shop_preview(ref, (ox, 0.6, oz), 180.0, "EastSpeedShop", indent=4))
            elif bx == grid_radius:
                ground_items.append(
                    make_part_xml(
                        ref,
                        "BeachSand",
                        (usable, 0.7, usable),
                        (ox, 0.35, oz),
                        (235, 205, 145),
                        MAT_SAND,
                        indent=4,
                    )
                )
                ground_items.append(
                    make_part_xml(
                        ref,
                        "BoardwalkDeck",
                        (28.0, 1.0, usable),
                        (ox - 38.0, 0.5, oz),
                        (155, 108, 68),
                        MAT_WOOD_PLANKS,
                        indent=4,
                    )
                )
                zones_items.append(
                    build_stunt_ramp_preview(ref, (ox + 10.0, 0.7, oz), 0.0, 18.0, 8.0, 24.0, "BoardwalkStuntJump", indent=4)
                )
            elif bx <= -2 and bz <= -1:
                buildings_items.append(
                    make_part_xml(
                        ref,
                        "IndustrialWarehouse",
                        (56.0, 26.0, 40.0),
                        (ox + 28.0, 13.6, oz + 25.0),
                        (95, 65, 55),
                        MAT_CORRODED_METAL,
                        indent=4,
                    )
                )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "ConstructionCraneMast",
                        (5.0, 85.0, 5.0),
                        (ox - 35.0, 45.1, oz - 35.0),
                        (245, 185, 30),
                        MAT_METAL,
                        indent=4,
                    )
                )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "ConstructionCraneJib",
                        (75.0, 4.0, 4.0),
                        (ox - 10.0, 86.6, oz - 35.0),
                        (245, 185, 30),
                        MAT_METAL,
                        indent=4,
                    )
                )
            elif bx <= -2 and bz >= 1:
                ground_items.append(
                    make_part_xml(
                        ref,
                        "ParkLawn",
                        (usable - 16.0, 0.8, usable - 16.0),
                        (ox, 0.4, oz),
                        (52, 135, 65),
                        MAT_GRASS,
                        indent=4,
                    )
                )
                ground_items.append(
                    make_part_xml(
                        ref,
                        "ParkPond",
                        (46.0, 0.9, 34.0),
                        (ox - 22.0, 0.5, oz + 18.0),
                        (45, 155, 235),
                        MAT_GLASS,
                        indent=4,
                    )
                )
                zones_items.append(
                    build_stunt_ramp_preview(
                        ref, (ox - 22.0, 0.8, oz - 18.0), 180.0, 20.0, 9.0, 26.0, "ParkLakeMegaJump", indent=4
                    )
                )
            elif abs(bx) <= 1 and abs(bz) <= 1:
                is_leo = (bx == 0 and bz == -1) or (bx == 1 and bz == -1)
                if bx == 0 and bz == -1:
                    h = 195.0
                elif bx == 1 and bz == -1:
                    h = 175.0
                else:
                    h = 110.0 + ((abs(bx * 3 + bz * 5) % 4) * 18.0)
                col = (182, 206, 232) if is_leo else (210, 220, 235)
                t_name = "LeoTower" if (bx == 0 and bz == -1) else "DowntownTower"
                x_off = 44.0 if bx == 0 else 28.0
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox - x_off, 0.6, oz - 26.0),
                        40.0,
                        40.0,
                        h,
                        col,
                        t_name,
                        is_leo_tower=is_leo,
                        indent=4,
                    )
                )
                if is_leo:
                    zones_items.append(
                        build_stunt_ramp_preview(
                            ref,
                            (ox - x_off, 0.6 + h, oz - 26.0 - 40.0 * 0.3),
                            0.0,
                            26.0,
                            8.0,
                            32.0,
                            "RooftopMegaJump",
                            indent=4,
                        )
                    )
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox + x_off, 0.6, oz + 26.0),
                        38.0,
                        38.0,
                        92.0,
                        (226, 218, 204),
                        "GlassOfficeTower",
                        is_leo_tower=False,
                        indent=4,
                    )
                )
            else:
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox - 26.0, 0.6, oz - 24.0),
                        36.0,
                        36.0,
                        48.0,
                        (228, 178, 152),
                        "CityBlockBuilding",
                        is_leo_tower=False,
                        indent=4,
                    )
                )
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox + 26.0, 0.6, oz + 24.0),
                        34.0,
                        34.0,
                        38.0,
                        (195, 215, 232),
                        "CommercialStore",
                        is_leo_tower=False,
                        indent=4,
                    )
                )

    subfolders = [
        make_folder_item(ref, "Ground", ground_items, indent=3),
        make_folder_item(ref, "Roads", roads_items, indent=3),
        make_folder_item(ref, "Landmarks", landmarks_items, indent=3),
        make_folder_item(ref, "InteractiveZones", zones_items, indent=3),
        make_folder_item(ref, "Buildings", buildings_items, indent=3),
    ]
    return make_model_xml(ref, "LeoCity_EditPreview", subfolders, indent=2)


def build_workspace_xml(ref: RefGen) -> str:
    ws_ref = ref.next()
    cam_ref = ref.next()
    terrain_ref = ref.next()
    spawn_ref = ref.next()

    cam_cframe_xml = cframe_look_at_xml((0.0, 45.0, 85.0), (0.0, 10.0, 0.0), indent=4, name="CFrame")
    cam_focus_xml = cframe_yaw_xml(0.0, 10.0, 0.0, 0.0, indent=4, name="Focus")
    edit_preview_xml = build_leo_city_edit_preview_xml(ref)
    spawn_color_xml = color_xml(55, 65, 85, indent=4)

    return f"""\t<Item class="Workspace" referent="{ws_ref}">
\t\t<Properties>
\t\t\t<string name="Name">Workspace</string>
\t\t\t<Ref name="CurrentCamera">{cam_ref}</Ref>
\t\t\t<float name="Gravity">196.2</float>
\t\t\t<token name="StreamingEnabled">1</token>
\t\t</Properties>
\t\t<Item class="Camera" referent="{cam_ref}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Camera</string>
\t\t\t\t<token name="CameraType">0</token>
\t\t\t\t<float name="FieldOfView">70</float>
{cam_cframe_xml}
{cam_focus_xml}
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="Terrain" referent="{terrain_ref}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Terrain</string>
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="SpawnLocation" referent="{spawn_ref}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">SpawnLocation</string>
\t\t\t\t<bool name="Anchored">true</bool>
\t\t\t\t<bool name="CanCollide">true</bool>
\t\t\t\t<bool name="Neutral">true</bool>
\t\t\t\t<float name="Transparency">0</float>
\t\t\t\t<token name="Material">{MAT_CONCRETE}</token>
\t\t\t\t<token name="TopSurface">0</token>
\t\t\t\t<token name="BottomSurface">0</token>
\t\t\t\t<Vector3 name="size">
\t\t\t\t\t<X>16</X>
\t\t\t\t\t<Y>1</Y>
\t\t\t\t\t<Z>16</Z>
\t\t\t\t</Vector3>
{spawn_color_xml}
{cframe_yaw_xml(0.0, 0.5, 25.0, 0.0, indent=4)}
\t\t\t</Properties>
\t\t</Item>
{edit_preview_xml}
\t</Item>"""


def build_lighting_xml(ref: RefGen) -> str:
    return f"""\t<Item class="Lighting" referent="{ref.next()}">
\t\t<Properties>
\t\t\t<string name="Name">Lighting</string>
\t\t\t<float name="Brightness">3.6</float>
\t\t\t<float name="ClockTime">13.5</float>
\t\t\t<float name="GeographicLatitude">34</float>
\t\t\t<bool name="GlobalShadows">true</bool>
\t\t\t<Color3 name="Ambient"><R>0.6078</R><G>0.6353</G><B>0.6863</B></Color3>
\t\t\t<Color3 name="OutdoorAmbient"><R>0.7255</R><G>0.7529</G><B>0.8039</B></Color3>
\t\t</Properties>
\t\t<Item class="Atmosphere" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Atmosphere</string>
\t\t\t\t<float name="Density">0.16</float>
\t\t\t\t<float name="Offset">0.10</float>
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="BloomEffect" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Bloom</string>
\t\t\t\t<bool name="Enabled">true</bool>
\t\t\t\t<float name="Intensity">0.30</float>
\t\t\t\t<float name="Size">18</float>
\t\t\t\t<float name="Threshold">1.70</float>
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
    print("Pre-baked Workspace.LeoCity_EditPreview + Camera CFrame at (0, 45, 85) -> (0, 10, 0)")
    print(f"Packed {len(manifest)} Luau scripts:")
    for container, name, path in manifest:
        rel = path.relative_to(ROOT_DIR)
        print(f"  - [{container}] {name}  ({rel})")
    print(f"Total file size: {OUTPUT_FILE.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
