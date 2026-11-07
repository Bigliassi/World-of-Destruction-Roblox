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
MAT_SNOW = 1328
MAT_ICE = 1536
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
    """
    Seamless 1-piece low-angle steel stunt ramp (no stepped blocks or giant yellow walls).
    """
    ramp_width = max(width, 26.0)
    total_len = max(length, 38.0)
    ramp_h = min(max(height, 5.5), 7.2)
    y0 = -0.15

    parts: List[str] = [
        # Seamless 1-piece low-angle dark steel WedgePart
        make_part_xml(
            ref,
            "RampDeckWedge",
            (ramp_width, ramp_h, total_len),
            rotate_offset(pos, yaw_deg, (0.0, y0 + ramp_h * 0.5, 0.0)),
            (42, 48, 58),
            MAT_METAL,
            yaw_deg,
            class_name="WedgePart",
            indent=indent + 1,
        ),
        # Flush ground transition plate so tires never snag
        make_part_xml(
            ref,
            "ApproachTransitionPlate",
            (ramp_width, 0.25, 4.0),
            rotate_offset(pos, yaw_deg, (0.0, 0.05, total_len * 0.5 + 1.8)),
            (54, 60, 72),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        # Low-profile side guide curbs
        make_part_xml(
            ref,
            "LeftEdgeTrim",
            (0.55, 0.45, total_len),
            rotate_offset(pos, yaw_deg, (-ramp_width * 0.5 + 0.28, ramp_h * 0.48, 0.0)),
            (255, 190, 45),
            MAT_NEON,
            yaw_deg,
            can_collide=False,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "RightEdgeTrim",
            (0.55, 0.45, total_len),
            rotate_offset(pos, yaw_deg, (ramp_width * 0.5 - 0.28, ramp_h * 0.48, 0.0)),
            (255, 190, 45),
            MAT_NEON,
            yaw_deg,
            can_collide=False,
            indent=indent + 1,
        ),
        # Subtle launch lip strip
        make_part_xml(
            ref,
            "LaunchLipStrip",
            (ramp_width - 1.2, 0.35, 1.4),
            rotate_offset(pos, yaw_deg, (0.0, ramp_h - 0.1, -total_len * 0.5 + 0.7)),
            (85, 225, 255),
            MAT_NEON,
            yaw_deg,
            can_collide=False,
            indent=indent + 1,
        ),
    ]
    return make_model_xml(ref, label_text, parts, indent=indent)


def build_speed_shop_preview(
    ref: RefGen,
    pos: Tuple[float, float, float],
    yaw_deg: float,
    name: str = "SpeedShop",
    indent: int = 4,
) -> str:
    base_pos = (pos[0], 0.0, pos[2])
    parts: List[str] = [
        make_part_xml(
            ref,
            "ShowroomFloor",
            (44.0, 0.40, 36.0),
            rotate_offset(base_pos, yaw_deg, (0.0, 0.26, 0.0)),
            (28, 32, 42),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "BackWall",
            (42.0, 22.0, 2.0),
            rotate_offset(base_pos, yaw_deg, (0.0, 11.4, 14.0)),
            (22, 26, 36),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "LeftWall",
            (2.0, 22.0, 26.0),
            rotate_offset(base_pos, yaw_deg, (-20.0, 11.4, 2.0)),
            (22, 26, 36),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "RightWall",
            (2.0, 22.0, 26.0),
            rotate_offset(base_pos, yaw_deg, (20.0, 11.4, 2.0)),
            (22, 26, 36),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "Roof",
            (44.0, 1.6, 30.0),
            rotate_offset(base_pos, yaw_deg, (0.0, 22.8, 2.0)),
            (18, 20, 28),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "ShowroomGlass",
            (38.0, 16.0, 0.6),
            rotate_offset(base_pos, yaw_deg, (0.0, 8.8, -10.4)),
            (60, 210, 255),
            MAT_GLASS,
            yaw_deg,
            transparency=0.55,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "SignBoard",
            (34.0, 6.0, 1.5),
            rotate_offset(base_pos, yaw_deg, (0.0, 26.8, -9.5)),
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
            (18.0, 0.24, 14.0),
            rotate_offset(base_pos, yaw_deg, (0.0, 0.58, -16.0)),
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
    base_pos = (pos[0], 0.0, pos[2])
    parts: List[str] = [
        make_part_xml(
            ref,
            "BayFloor",
            (32.0, 0.40, 32.0),
            rotate_offset(base_pos, yaw_deg, (0.0, 0.26, 0.0)),
            (34, 38, 46),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "LeftWall",
            (2.0, 16.0, 26.0),
            rotate_offset(base_pos, yaw_deg, (-13.0, 8.4, 0.0)),
            (48, 52, 62),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "RightWall",
            (2.0, 16.0, 26.0),
            rotate_offset(base_pos, yaw_deg, (13.0, 8.4, 0.0)),
            (48, 52, 62),
            MAT_CONCRETE,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "Roof",
            (30.0, 1.5, 28.0),
            rotate_offset(base_pos, yaw_deg, (0.0, 16.8, 0.0)),
            (28, 32, 40),
            MAT_METAL,
            yaw_deg,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "MechanicSign",
            (26.0, 5.0, 1.4),
            rotate_offset(base_pos, yaw_deg, (0.0, 20.1, -12.0)),
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
            (18.0, 0.24, 20.0),
            rotate_offset(base_pos, yaw_deg, (0.0, 0.58, 0.0)),
            (50, 255, 110),
            MAT_NEON,
            yaw_deg,
            transparency=0.20,
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
    """
    High-detail Manhattan Art Deco stepped setback tower with snow-dusted cornice ledges,
    vertical stone piers, and subtle recessed warm golden apartment/office window mullions.
    """
    cx, cy, cz = center
    lower_h = height * 0.72
    mid_h = height * 0.28
    pier_col = (max(18, tint[0] - 14), max(20, tint[1] - 14), max(24, tint[2] - 12))
    trim_col = (148, 128, 84) if is_leo_tower else (96, 104, 118)
    snow_col = (236, 242, 250)
    warm_mullion = (235, 202, 145)

    parts: List[str] = [
        # Base Podium & Art Deco Main Shaft
        make_part_xml(
            ref,
            "Shaft",
            (width, lower_h, depth),
            (cx, cy + lower_h * 0.5, cz),
            tint,
            MAT_CONCRETE,
            indent=indent + 1,
        ),
        # First Art Deco Setback Tier
        make_part_xml(
            ref,
            "MidTierSetback",
            (width * 0.80, mid_h, depth * 0.80),
            (cx, cy + lower_h + mid_h * 0.5, cz),
            pier_col,
            MAT_CONCRETE,
            indent=indent + 1,
        ),
        # Cornice Ledge + Snow Cap
        make_part_xml(
            ref,
            "ArtDecoCornice",
            (width + 1.4, 1.4, depth + 1.4),
            (cx, cy + lower_h, cz),
            trim_col,
            MAT_METAL,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "SnowDustedLedge",
            (width + 1.8, 0.4, depth + 1.8),
            (cx, cy + lower_h + 0.9, cz),
            snow_col,
            MAT_SNOW,
            can_collide=False,
            indent=indent + 1,
        ),
        # Recessed Dark Brass & Glass Lobby
        make_part_xml(
            ref,
            "GlassLobby",
            (width * 0.82, 14.0, depth + 0.6),
            (cx, cy + 7.0, cz),
            (255, 205, 125),
            MAT_GLASS,
            transparency=0.35,
            indent=indent + 1,
        ),
    ]

    floors = max(4, min(12, int((height - 16.0) // 16)))
    for f in range(1, floors + 1):
        y = cy + 16.0 + (f - 0.5) * ((height - 20.0) / floors)
        tier_scale = 0.80 if (y - cy) > lower_h else 1.0
        parts.append(
            make_part_xml(
                ref,
                "WindowBandZ",
                ((width - 4.4) * tier_scale, 2.2, (depth - 0.2) * tier_scale),
                (cx, y, cz),
                warm_mullion,
                MAT_SMOOTH_PLASTIC,
                indent=indent + 1,
            )
        )
        parts.append(
            make_part_xml(
                ref,
                "WindowBandX",
                ((width - 0.2) * tier_scale, 2.2, (depth - 4.4) * tier_scale),
                (cx, y, cz),
                warm_mullion,
                MAT_SMOOTH_PLASTIC,
                indent=indent + 1,
            )
        )

    crown_h = max(10.0, height * 0.14)
    crown_children: List[str] = []
    if is_leo_tower:
        crown_children = [
            make_surface_sign_xml(ref, "LEO TOWER", (255, 215, 65), FACE_FRONT, indent + 2),
            make_surface_sign_xml(ref, "LEO TOWER", (255, 215, 65), FACE_BACK, indent + 2),
        ]
    parts.append(
        make_part_xml(
            ref,
            "Crown",
            (width * 0.64, crown_h, depth * 0.64),
            (cx, cy + height + crown_h * 0.5, cz),
            trim_col,
            MAT_METAL,
            children_xml=crown_children,
            indent=indent + 1,
        )
    )
    parts.append(
        make_part_xml(
            ref,
            "RoofSnowCap",
            (width * 0.84 + 2.2, 0.45, depth * 0.84 + 2.2),
            (cx, cy + height + 1.8, cz),
            snow_col,
            MAT_SNOW,
            can_collide=False,
            indent=indent + 1,
        )
    )

    if is_leo_tower:
        parts.append(
            make_part_xml(
                ref,
                "LeoSpire",
                (3.2, 34.0, 3.2),
                (cx, cy + height + crown_h + 17.0, cz),
                (255, 215, 65),
                MAT_NEON,
                can_collide=False,
                indent=indent + 1,
            )
        )

    return make_model_xml(ref, name, parts, indent=indent)


def build_christmas_tree_preview(
    ref: RefGen,
    pos: Tuple[float, float, float],
    height: float = 16.0,
    name: str = "SnowyChristmasTree",
    indent: int = 4,
) -> str:
    px, py, pz = pos
    pine_col = (26, 76, 46)
    snow_col = (238, 244, 252)
    scale = height / 16.0
    parts: List[str] = [
        make_part_xml(
            ref,
            "Trunk",
            (1.8 * scale, 5.2 * scale, 1.8 * scale),
            (px, py + 2.6 * scale, pz),
            (104, 68, 42),
            MAT_WOOD,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "PineTier1",
            (8.2 * scale, 4.6 * scale, 8.2 * scale),
            (px, py + 6.2 * scale, pz),
            pine_col,
            MAT_GRASS,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "SnowCap1",
            (8.5 * scale, 0.65 * scale, 8.5 * scale),
            (px, py + 8.3 * scale, pz),
            snow_col,
            MAT_SNOW,
            can_collide=False,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "PineTier2",
            (6.0 * scale, 4.2 * scale, 6.0 * scale),
            (px, py + 10.2 * scale, pz),
            pine_col,
            MAT_GRASS,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "SnowCap2",
            (6.3 * scale, 0.65 * scale, 6.3 * scale),
            (px, py + 12.1 * scale, pz),
            snow_col,
            MAT_SNOW,
            can_collide=False,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "PineTier3",
            (3.8 * scale, 3.8 * scale, 3.8 * scale),
            (px, py + 13.8 * scale, pz),
            pine_col,
            MAT_GRASS,
            indent=indent + 1,
        ),
        make_part_xml(
            ref,
            "GoldenStarTopper",
            (1.5 * scale, 1.5 * scale, 0.6 * scale),
            (px, py + 16.2 * scale, pz),
            (255, 220, 85),
            MAT_NEON,
            can_collide=False,
            indent=indent + 1,
        ),
    ]
    return make_model_xml(ref, name, parts, indent=indent)


def build_leo_city_edit_preview_xml(ref: RefGen) -> str:
    """
    Builds Workspace.LeoCity_EditPreview so that opening WorldOfDestruction.rbxlx in Roblox Studio
    Edit Mode immediately displays the moody dark cloudy/snowy NYC Leo City (tight 140-stud blocks,
    zero-flicker Y elevations, and Tier 1..5 destruction targets) in front of the viewport camera.
    Replaced cleanly at runtime by WorldBuilderService.script.luau.
    """
    block_size = 180.0
    road_width = 38.0
    grid_radius = 3
    usable = block_size - road_width
    total_span = (grid_radius * 2 + 1) * block_size + 240.0
    grid_extent = (grid_radius + 1) * block_size

    ground_items: List[str] = [
        make_part_xml(
            ref,
            "CityBaseplate",
            (total_span, 4.0, total_span),
            (0.0, -2.2, 0.0),
            (36, 40, 48),
            MAT_CONCRETE,
            indent=4,
        ),
        make_part_xml(
            ref,
            "OceanWater",
            (360.0, 3.6, total_span),
            ((grid_radius + 1.2) * block_size, -1.8, 0.0),
            (22, 46, 70),
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
            (road_width, 0.32, grid_extent * 2.0),
            (0.0, 0.0, 0.0),
            (24, 28, 36),
            MAT_ASPHALT,
            indent=4,
        )
    )
    for rx in road_lines:
        roads_items.append(
            make_part_xml(
                ref,
                "RoadNS",
                (road_width, 0.32, grid_extent * 2.0),
                (rx, 0.0, 0.0),
                (26, 30, 38),
                MAT_ASPHALT,
                indent=4,
            )
        )
        for z in range(int(-grid_extent + 20), int(grid_extent - 20) + 1, 56):
            roads_items.append(
                make_part_xml(
                    ref,
                    "LaneDashNS",
                    (0.8, 0.08, 12.0),
                    (rx, 0.21, float(z)),
                    (230, 185, 55),
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
                (0.0, 0.01, rz),
                (26, 30, 38),
                MAT_ASPHALT,
                indent=4,
            )
        )
        for x in range(int(-grid_extent + 20), int(grid_extent - 20) + 1, 56):
            roads_items.append(
                make_part_xml(
                    ref,
                    "LaneDashEW",
                    (12.0, 0.08, 0.8),
                    (float(x), 0.21, rz),
                    (230, 185, 55),
                    MAT_SMOOTH_PLASTIC,
                    indent=4,
                )
            )

    # Crosswalks around the central Downtown & Leo Plaza intersections
    for rx in (-210.0, -70.0, 70.0, 210.0):
        for rz in (-210.0, -70.0, 70.0, 210.0):
            for s in (-2, -1, 1, 2):
                roads_items.append(
                    make_part_xml(
                        ref,
                        "CrosswalkN",
                        (3.2, 0.08, 1.2),
                        (rx + s * 5.5, 0.22, rz - road_width * 0.5 - 2.0),
                        (212, 218, 228),
                        MAT_SMOOTH_PLASTIC,
                        indent=4,
                    )
                )
                roads_items.append(
                    make_part_xml(
                        ref,
                        "CrosswalkE",
                        (1.2, 0.08, 3.2),
                        (rx + road_width * 0.5 + 2.0, 0.22, rz + s * 5.5),
                        (212, 218, 228),
                        MAT_SMOOTH_PLASTIC,
                        indent=4,
                    )
                )

    # City blocks, wet slate sidewalks (Y = 0.20, Size Y = 0.20 -> top Y = 0.30), Leo Plaza fountain, Speed Shops, Mechanic Bays, Stunt Ramps, and Art Deco Skyscrapers
    for bx in range(-grid_radius, grid_radius + 1):
        for bz in range(-grid_radius, grid_radius + 1):
            ox, oz = bx * block_size, bz * block_size
            if bx != 0:
                ground_items.append(
                    make_part_xml(
                        ref,
                        "SidewalkBlock",
                        (usable, 0.20, usable),
                        (ox, 0.20, oz),
                        (68, 74, 84),
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
                        (side_w, 0.20, usable),
                        (ox - (road_width * 0.5 + side_w * 0.5), 0.20, oz),
                        (68, 74, 84),
                        MAT_CONCRETE,
                        indent=4,
                    )
                )
                ground_items.append(
                    make_part_xml(
                        ref,
                        "SidewalkBlockE",
                        (side_w, 0.20, usable),
                        (ox + (road_width * 0.5 + side_w * 0.5), 0.20, oz),
                        (68, 74, 84),
                        MAT_CONCRETE,
                        indent=4,
                    )
                )

            if bx == 0 and bz == 0:
                # 52-stud Rockefeller / Plaza Christmas Tree at (-46, 0.3, 18) & Marble Fountain at (-46, 0.3, 42)
                landmarks_items.append(
                    build_christmas_tree_preview(
                        ref,
                        (ox - 46.0, 0.3, oz + 18.0),
                        height=52.0,
                        name="RockefellerPlazaChristmasTree",
                        indent=4,
                    )
                )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "LeoPlazaFountain",
                        (16.0, 3.2, 16.0),
                        (ox - 46.0, 1.8, oz + 42.0),
                        (235, 238, 245),
                        MAT_MARBLE,
                        indent=4,
                    )
                )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "FountainWaterTier",
                        (12.0, 1.4, 12.0),
                        (ox - 46.0, 3.6, oz + 42.0),
                        (165, 215, 248),
                        MAT_ICE,
                        transparency=0.15,
                        indent=4,
                    )
                )
                # Festive Holiday Gift Stacks along the curb/plaza edges (never blocking 5th Avenue center driving lane!)
                for gx_off, gz_off in ((-22.0, 8.0), (22.0, 8.0), (-22.0, -18.0), (22.0, -18.0)):
                    landmarks_items.append(
                        make_part_xml(
                            ref,
                            "HolidayGiftStack",
                            (3.6, 2.8, 3.6),
                            (ox + gx_off, 1.7, oz + gz_off),
                            (186, 32, 38),
                            MAT_SMOOTH_PLASTIC,
                            indent=4,
                        )
                    )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "ArmoredCashTruck",
                        (6.8, 4.4, 15.6),
                        (ox + 26.0, 2.5, oz + 44.0),
                        (34, 40, 52),
                        MAT_METAL,
                        indent=4,
                    )
                )
                landmarks_items.append(
                    make_part_xml(
                        ref,
                        "MegaCorpBankVault",
                        (10.5, 8.2, 7.6),
                        (ox + 48.0, 4.4, oz + 44.0),
                        (235, 185, 32),
                        MAT_METAL,
                        indent=4,
                    )
                )
                # Stunt Ramp on side plaza at (-30, 0.3, -52) so 5th Avenue center canyon view is 100% open!
                zones_items.append(
                    build_stunt_ramp_preview(ref, (ox - 30.0, 0.3, oz - 52.0), 0.0, 24.0, 5.8, 34.0, "LeoPlazaRamp", indent=4)
                )
                zones_items.append(
                    build_speed_shop_preview(ref, (ox + 52.0, 0.0, oz - 22.0), -90.0, "PlazaSpeedShop", indent=4)
                )
                zones_items.append(
                    build_mechanic_bay_preview(ref, (ox - 52.0, 0.0, oz - 22.0), 90.0, "PlazaMechanicRepairBay", indent=4)
                )
            elif bx == 1 and bz == 0:
                zones_items.append(build_speed_shop_preview(ref, (ox, 0.0, oz - 24.0), -90.0, "SpeedShop", indent=4))
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox - 36.0, 0.3, oz + 34.0),
                        34.0,
                        34.0,
                        195.0,
                        (68, 76, 90),
                        "FifthAveEastTowerA",
                        indent=4,
                    )
                )
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox + 36.0, 0.3, oz + 34.0),
                        34.0,
                        34.0,
                        235.0,
                        (84, 76, 68),
                        "FifthAveEastTowerB",
                        indent=4,
                    )
                )
            elif (bx == -1 and bz == 0) or (bx <= -1 and bz >= 1):
                # Snowy Christmas Central Park: white snow lawn, Wollman Ice Skating Rink, and 48-stud Christmas Tree!
                ground_items.append(
                    make_part_xml(
                        ref,
                        "SnowyParkLawn",
                        (usable - 12.0, 0.24, usable - 12.0),
                        (ox, 0.24, oz),
                        (238, 244, 252),
                        MAT_SNOW,
                        indent=4,
                    )
                )
                ground_items.append(
                    make_part_xml(
                        ref,
                        "WollmanIceSkatingRink",
                        (54.0, 0.24, 40.0),
                        (ox - 14.0, 0.34, oz + 16.0),
                        (168, 214, 248),
                        MAT_ICE,
                        indent=4,
                    )
                )
                landmarks_items.append(
                    build_christmas_tree_preview(
                        ref,
                        (ox + 28.0, 0.36, oz - 18.0),
                        height=48.0,
                        name="CentralParkChristmasTree",
                        indent=4,
                    )
                )
                if bx == -1 and bz == 0:
                    zones_items.append(
                        build_mechanic_bay_preview(ref, (ox + 38.0, 0.0, oz - 36.0), 90.0, "MechanicRepairBay", indent=4)
                    )
                else:
                    zones_items.append(
                        build_stunt_ramp_preview(
                            ref, (ox - 14.0, 0.36, oz - 24.0), 180.0, 26.0, 6.2, 38.0, "ParkLakeMegaJump", indent=4
                        )
                    )
            elif bx == 0 and bz != 0:
                # 5TH AVENUE SKYSCRAPER CANYON: 4 tall Manhattan skyscrapers (160 to 310 studs tall) flanking both sides of 5th Avenue
                is_leo_block = bz == -1
                seed = abs(bz * 19)
                h_nw = 310.0 if is_leo_block else float(185 + (seed % 95))
                h_ne = 265.0 if is_leo_block else float(170 + ((seed + 37) % 105))
                h_sw = 240.0 if is_leo_block else float(160 + ((seed + 61) % 110))
                h_se = 280.0 if is_leo_block else float(195 + ((seed + 83) % 95))
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox - 44.0, 0.3, oz - 32.0),
                        36.0,
                        36.0,
                        h_nw,
                        (58, 68, 86),
                        "LeoTower" if is_leo_block else "FifthAveTowerNW",
                        is_leo_tower=is_leo_block,
                        indent=4,
                    )
                )
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox + 44.0, 0.3, oz - 32.0),
                        36.0,
                        36.0,
                        h_ne,
                        (76, 82, 96),
                        "FifthAveTowerNE",
                        indent=4,
                    )
                )
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox - 44.0, 0.3, oz + 32.0),
                        36.0,
                        36.0,
                        h_sw,
                        (88, 78, 70),
                        "FifthAveTowerSW",
                        indent=4,
                    )
                )
                buildings_items.append(
                    build_skyscraper_preview(
                        ref,
                        (ox + 44.0, 0.3, oz + 32.0),
                        36.0,
                        36.0,
                        h_se,
                        (64, 72, 86),
                        "FifthAveTowerSE",
                        indent=4,
                    )
                )
                if is_leo_block:
                    zones_items.append(
                        build_stunt_ramp_preview(
                            ref,
                            (ox - 44.0, 0.3 + h_nw, oz - 32.0 - 36.0 * 0.3),
                            0.0,
                            26.0,
                            6.5,
                            38.0,
                            "RooftopMegaJump",
                            indent=4,
                        )
                    )
                elif bz == -2:
                    zones_items.append(
                        build_mechanic_bay_preview(ref, (ox - 44.0, 0.0, oz), 90.0, "NorthMechanicRepairBay", indent=4)
                    )
            elif bx == 2 and bz == 2:
                zones_items.append(build_speed_shop_preview(ref, (ox, 0.0, oz), 180.0, "EastSpeedShop", indent=4))
            elif bx == -2 and bz == 2:
                buildings_items.append(
                    make_part_xml(
                        ref,
                        "BoomGasStationCanopy",
                        (44.0, 2.2, 28.0),
                        (ox, 18.6, oz),
                        (185, 38, 38),
                        MAT_METAL,
                        indent=4,
                    )
                )
            elif bx == grid_radius:
                ground_items.append(
                    make_part_xml(
                        ref,
                        "FrostyPierDeck",
                        (usable, 0.24, usable),
                        (ox, 0.24, oz),
                        (82, 88, 98),
                        MAT_CONCRETE,
                        indent=4,
                    )
                )
                ground_items.append(
                    make_part_xml(
                        ref,
                        "BoardwalkDeck",
                        (24.0, 0.24, usable),
                        (ox - 26.0, 0.34, oz),
                        (96, 68, 48),
                        MAT_WOOD_PLANKS,
                        indent=4,
                    )
                )
                zones_items.append(
                    build_stunt_ramp_preview(ref, (ox + 8.0, 0.36, oz), 0.0, 26.0, 6.5, 38.0, "BoardwalkStuntJump", indent=4)
                )
            elif bx == -3 and bz == -3:
                # Compact Hudson Container Dock at far NW corner (without stick cranes cluttering the skyline!)
                buildings_items.append(
                    make_part_xml(
                        ref,
                        "ShippingContainerRed",
                        (8.4, 8.6, 22.0),
                        (ox + 13.4, 4.6, oz + 14.0),
                        (195, 48, 38),
                        MAT_METAL,
                        indent=4,
                    )
                )
                buildings_items.append(
                    make_part_xml(
                        ref,
                        "ShippingContainerBlue",
                        (8.4, 8.6, 22.0),
                        (ox + 22.6, 4.6, oz + 14.0),
                        (34, 96, 178),
                        MAT_METAL,
                        indent=4,
                    )
                )
                buildings_items.append(
                    make_part_xml(
                        ref,
                        "ShippingContainerGold",
                        (8.4, 8.6, 22.0),
                        (ox + 13.4, 13.4, oz + 14.0),
                        (228, 162, 32),
                        MAT_METAL,
                        indent=4,
                    )
                )
            else:
                # Dense 4-Tower Manhattan Skyscraper Block (135 to 280 studs tall)
                seed = abs(bx * 5 + bz * 11)
                quads = [
                    (-34.0, -34.0, 36.0, 36.0, 145.0 + float((seed * 13) % 75), (74, 80, 92)),
                    (34.0, -34.0, 34.0, 34.0, 175.0 + float((seed * 17) % 85), (88, 76, 68)),
                    (-34.0, 34.0, 34.0, 34.0, 195.0 + float((seed * 23) % 75), (62, 70, 84)),
                    (34.0, 34.0, 36.0, 36.0, 215.0 + float((seed * 29) % 70), (94, 86, 76)),
                ]
                for q_idx, (qx, qz, qw, qd, qh, qtint) in enumerate(quads, start=1):
                    buildings_items.append(
                        build_skyscraper_preview(
                            ref,
                            (ox + qx, 0.3, oz + qz),
                            qw,
                            qd,
                            qh,
                            qtint,
                            f"ManhattanTower_{q_idx}",
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
\t\t\t<float name="Brightness">2.15</float>
\t\t\t<float name="ClockTime">16.4</float>
\t\t\t<float name="GeographicLatitude">40.7</float>
\t\t\t<bool name="GlobalShadows">true</bool>
\t\t\t<Color3 name="Ambient"><R>0.3059</R><G>0.3451</G><B>0.4235</B></Color3>
\t\t\t<Color3 name="OutdoorAmbient"><R>0.4000</R><G>0.4471</G><B>0.5333</B></Color3>
\t\t\t<Color3 name="ColorShift_Top"><R>0.7255</R><G>0.7843</G><B>0.8824</B></Color3>
\t\t</Properties>
\t\t<Item class="Atmosphere" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Atmosphere</string>
\t\t\t\t<float name="Density">0.34</float>
\t\t\t\t<float name="Offset">0.18</float>
\t\t\t\t<float name="Haze">1.85</float>
\t\t\t\t<float name="Glare">0.20</float>
\t\t\t\t<Color3 name="Color"><R>0.5176</R><G>0.5647</G><B>0.6510</B></Color3>
\t\t\t\t<Color3 name="Decay"><R>0.2902</R><G>0.3294</G><B>0.4078</B></Color3>
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="BloomEffect" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Bloom</string>
\t\t\t\t<bool name="Enabled">true</bool>
\t\t\t\t<float name="Intensity">0.52</float>
\t\t\t\t<float name="Size">24</float>
\t\t\t\t<float name="Threshold">1.15</float>
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
