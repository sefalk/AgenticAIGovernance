"""Render the Red-phase-block artefact as an animated GIF for the AAIG talk.

Draws five synthetic terminal frames (see talk-2026-07-29-artefacts.md,
artefact 1) and writes an animated GIF plus a static fallback PNG of the
decisive frame.

Content is synthetic: generic order/refund domain, no real project data.

Usage:
    python render-red-phase-gif.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------- appearance

WIDTH, HEIGHT = 1280, 600
MARGIN_X, MARGIN_Y = 44, 34
FONT_SIZE = 23
LINE_H = 32

BG = (13, 17, 23)
CHROME = (22, 27, 34)
BORDER = (48, 54, 61)

FG = (201, 209, 217)
DIM = (110, 118, 129)
GREEN = (63, 185, 80)
RED = (248, 81, 73)
YELLOW = (210, 153, 34)
BLUE = (88, 166, 255)
PURPLE = (188, 140, 255)

FONT_PATH = r"C:\Windows\Fonts\consola.ttf"
FONT_BOLD_PATH = r"C:\Windows\Fonts\consolab.ttf"

# Per-frame duration in milliseconds. Frame 5 is held longest.
DURATIONS = [3000, 4000, 2800, 4200, 3600]

OUT_DIR = Path(__file__).resolve().parent / "assets"
GIF_PATH = OUT_DIR / "red-phase-block.gif"
FALLBACK_PATH = OUT_DIR / "red-phase-block-fallback.png"

# ------------------------------------------------------------------- content
# Each line is (text, colour). None marks a blank line.

FRAMES: list[tuple[str, list[tuple[str, tuple[int, int, int]] | None]]] = [
    (
        "1 / 5   dispatch",
        [
            ("coordinator \u2192 test-writer", PURPLE),
            ("\u2500" * 62, BORDER),
            None,
            ("Task     : REQ-114 \u2014 partial refund window", FG),
            ("Phase    : RED", YELLOW),
            None,
            ("Contract : Orders returned between 30 and 60 days after", FG),
            ("           delivery receive a 50% refund. Outside that", FG),
            ("           window the current behaviour is unchanged.", FG),
            None,
            ("Exit gate: new tests MUST fail against current", FG),
            ("           production code.", FG),
        ],
    ),
    (
        "2 / 5   what comes back",
        [
            ("tests/domain/test_refund_policy.py", BLUE),
            ("\u2500" * 62, BORDER),
            None,
            ("# copilot:generated | test-writer | 2026-08-10", DIM),
            None,
            ("def test_refund_after_return_window() -> None:", FG),
            ("    order = Order(total=100.00, days_since_delivery=45)", FG),
            ("    assert refund_amount(order) == 0.00", FG),
            None,
            ("well-formed \u00b7 typed \u00b7 marked \u00b7 readable", DIM),
            ("\u2026 and it asserts what the code already does,", DIM),
            ("    not what the requirement asks for.", DIM),
        ],
    ),
    (
        "3 / 5   the run",
        [
            ("$ pytest tests/ -q --tb=line --no-header", FG),
            None,
            ("tests/domain/test_refund_policy.py .            [100%]", FG),
            None,
            ("1 passed in 0.31s", GREEN),
            None,
            ("\u2500" * 62, BORDER),
            None,
            ("In CI this is a pass.", DIM),
        ],
    ),
    (
        "4 / 5   the hook",
        [
            ("test-writer : SubagentStop", PURPLE),
            ("\u2500" * 62, BORDER),
            None,
            ("{", FG),
            ('  "hookSpecificOutput": {', FG),
            ('    "hookEventName": "Stop",', FG),
            ('    "decision": "block",', RED),
            ('    "reason": "Red phase violation: all tests PASS.', FG),
            ('       New tests must FAIL against the existing', FG),
            ('       production code to express a genuine', FG),
            ('       requirement gap."', FG),
            ("  }", FG),
            ("}", FG),
        ],
    ),
    (
        "5 / 5   the consequence",
        [
            ("test-writer:Stop   \u2716  BLOCKED \u2014 Red gate", RED),
            ("\u2500" * 62, BORDER),
            None,
            ("Handoff to implementer refused.", FG),
            ("Returning to test-writer with the block reason.", FG),
            ("Attempt 2 of 2.", FG),
            None,
            ("The implementer was never invoked.", YELLOW),
            None,
            ("\u2500" * 62, BORDER),
            ("The gate stops the handoff, not the commit.", DIM),
        ],
    ),
]


def _load_fonts() -> tuple[ImageFont.FreeTypeFont, ImageFont.FreeTypeFont]:
    """Load the monospace fonts, falling back to the regular face if needed."""
    regular = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    try:
        bold = ImageFont.truetype(FONT_BOLD_PATH, FONT_SIZE)
    except OSError:
        bold = regular
    return regular, bold


def render_frame(
    caption: str,
    lines: list[tuple[str, tuple[int, int, int]] | None],
    font: ImageFont.FreeTypeFont,
    font_bold: ImageFont.FreeTypeFont,
) -> Image.Image:
    """Render a single terminal-styled frame.

    Parameters
    ----------
    caption
        Title-bar text, e.g. ``"3 / 5   the run"``.
    lines
        Body lines as ``(text, rgb)`` tuples; ``None`` renders a blank line.
    font, font_bold
        Monospace faces for body and title bar.

    Returns
    -------
    Image.Image
        The rendered RGB frame.
    """
    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    d = ImageDraw.Draw(img)

    # Title bar with the three window dots.
    bar_h = 56
    d.rectangle([0, 0, WIDTH, bar_h], fill=CHROME)
    d.line([0, bar_h, WIDTH, bar_h], fill=BORDER, width=2)
    for i, colour in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
        cx = 30 + i * 26
        d.ellipse([cx - 8, bar_h // 2 - 8, cx + 8, bar_h // 2 + 8], fill=colour)
    d.text((124, bar_h // 2 - FONT_SIZE // 2 - 2), caption, font=font_bold, fill=DIM)

    y = bar_h + MARGIN_Y
    for line in lines:
        if line is not None:
            text, colour = line
            d.text((MARGIN_X, y), text, font=font, fill=colour)
        y += LINE_H

    d.rectangle([0, 0, WIDTH - 1, HEIGHT - 1], outline=BORDER, width=2)
    return img


def main() -> None:
    """Render all frames and write the GIF and the fallback still."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    font, font_bold = _load_fonts()

    frames = [render_frame(cap, lines, font, font_bold) for cap, lines in FRAMES]

    # Quantise to a shared adaptive palette so the GIF stays small.
    quantised = [f.quantize(colors=64, method=Image.Quantize.MEDIANCUT) for f in frames]

    quantised[0].save(
        GIF_PATH,
        save_all=True,
        append_images=quantised[1:],
        duration=DURATIONS,
        loop=0,
        optimize=True,
        disposal=2,
    )

    # Frame 4 (index 3) is the decisive one: the machine-issued block.
    frames[3].save(FALLBACK_PATH, optimize=True)

    print(f"GIF      : {GIF_PATH}  ({GIF_PATH.stat().st_size / 1024:.0f} KB)")
    print(f"fallback : {FALLBACK_PATH}  ({FALLBACK_PATH.stat().st_size / 1024:.0f} KB)")
    print(f"duration : {sum(DURATIONS) / 1000:.1f} s over {len(frames)} frames")


if __name__ == "__main__":
    main()
