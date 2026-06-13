"""Dataclass schema for exhibition hall scene specifications."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field


Vector3 = tuple[float, float, float]


@dataclass(frozen=True)
class NftSpec:
    """NFT artwork display parameters for a booth."""
    name: str = ""
    collection: str = ""
    art_style: str = "gradient_noise"  # gradient_noise | voronoi | geometric | plasma | mandala | pixel_art | fractal | nebula | flow_field
    art_seed: int = 0
    art_colors: list[str] = field(default_factory=list)  # hex colors for procedural art
    token_id: str = ""  # optional on-chain token identifier


@dataclass(frozen=True)
class RoomSpec:
    id: str
    dimensions: Vector3  # width, height, depth
    wall_color: str


@dataclass(frozen=True)
class BoothSpec:
    id: str
    position: Vector3  # x, y, z
    orientation: float
    nft: NftSpec | None = None  # optional NFT display parameters


@dataclass(frozen=True)
class LightSpec:
    position: Vector3
    color: str
    intensity: float


@dataclass(frozen=True)
class SceneSpec:
    theme_name: str
    global_color_palette: list[str]
    rooms: list[RoomSpec]
    booths: list[BoothSpec]
    lights: list[LightSpec]

    def to_json(self) -> str:
        """Serialize the scene specification to formatted JSON."""
        return json.dumps(asdict(self), indent=2)


EXAMPLE_SPEC = SceneSpec(
    theme_name="Future of Artifacts",
    global_color_palette=[
        "#F7F1E8",
        "#202124",
        "#4ECDC4",
        "#FF6B6B",
        "#FFD166",
    ],
    rooms=[
        RoomSpec(
            id="main_hall",
            dimensions=(24.0, 7.0, 32.0),
            wall_color="#F7F1E8",
        ),
    ],
    booths=[
        BoothSpec(
            id="booth_welcome",
            position=(0.0, 0.0, -10.0),
            orientation=0.0,
            nft=NftSpec(
                name="Genesis Wave",
                collection="Future Artifacts",
                art_style="gradient_noise",
                art_seed=42,
                art_colors=["#4ECDC4", "#202124", "#FFD166"],
            ),
        ),
        BoothSpec(
            id="booth_ai_showcase",
            position=(-6.0, 0.0, 2.5),
            orientation=45.0,
            nft=NftSpec(
                name="Neural Bloom",
                collection="Future Artifacts",
                art_style="nebula",
                art_seed=137,
                art_colors=["#FF6B6B", "#202124", "#F7F1E8", "#4ECDC4"],
            ),
        ),
        BoothSpec(
            id="booth_web3_lab",
            position=(6.0, 0.0, 2.5),
            orientation=-45.0,
            nft=NftSpec(
                name="Chain Reaction",
                collection="Future Artifacts",
                art_style="fractal",
                art_seed=256,
                art_colors=["#FFD166", "#4ECDC4", "#202124", "#FF6B6B"],
            ),
        ),
    ],
    lights=[
        LightSpec(
            position=(0.0, 6.5, -8.0),
            color="#FFFFFF",
            intensity=900.0,
        ),
        LightSpec(
            position=(-7.0, 4.5, 4.0),
            color="#BFEFFF",
            intensity=450.0,
        ),
        LightSpec(
            position=(7.0, 4.5, 4.0),
            color="#FFE3B0",
            intensity=450.0,
        ),
    ],
)
