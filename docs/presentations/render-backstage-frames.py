"""Render the backstage view of the Red-phase block as five still frames.

Draws five synthetic terminal snapshots (see talk-2026-07-29-artefacts.md,
artefact 1) and writes each one as a separate PNG. Stills rather than an
animation on purpose: these frames carry evidence the audience is meant to
read, and the presenter needs to control when each one appears.

The front-of-house counterpart -- what the user sees in the chat while this
happens -- is animated instead, by ``render-chat-loop.py``.

Content is synthetic: generic order/refund domain, no real project data.

Usage:
    python render-backstage-frames.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------- appearance

# The canvas is measured from the content (see ``canvas_size``) rather than
# fixed, so no frame carries dead space and the box tracks any text edit.
MARGIN_X, MARGIN_Y = 44, 34
FONT_SIZE = 23
LINE_H = 32
BAR_H = 56
CAPTION_X = 124

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

OUT_DIR = Path(__file__).resolve().parent / "assets"

# Filename stems, in frame order. Numbered so they sort into narrative order
# in the file picker when they are dropped onto slides.
STEMS = [
    "backstage-1-dispatch",
    "backstage-2-what-comes-back",
    "backstage-3-the-run",
    "backstage-4-the-hook",
    "backstage-5-the-consequence",
]

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


def canvas_size(
    font: ImageFont.FreeTypeFont,
    font_bold: ImageFont.FreeTypeFont,
) -> tuple[int, int]:
    """Measure the smallest canvas that fits every frame.

    All frames share one size so the stills stay visually consistent on a
    slide; the size is the maximum over the whole set rather than per frame.

    Parameters
    ----------
    font, font_bold
        Monospace faces used for body and title-bar text.

    Returns
    -------
    tuple of (width, height)
        Pixel dimensions including margins, title bar and border.
    """
    text_w = 0.0
    caption_w = 0.0
    max_lines = 0
    for caption, lines in FRAMES:
        caption_w = max(caption_w, font_bold.getlength(caption))
        max_lines = max(max_lines, len(lines))
        for line in lines:
            if line is not None:
                text_w = max(text_w, font.getlength(line[0]))

    width = max(2 * MARGIN_X + text_w, CAPTION_X + caption_w + MARGIN_X)
    height = BAR_H + 2 * MARGIN_Y + (max_lines - 1) * LINE_H + FONT_SIZE + 5
    return round(width), round(height)


def render_frame(
    caption: str,
    lines: list[tuple[str, tuple[int, int, int]] | None],
    font: ImageFont.FreeTypeFont,
    font_bold: ImageFont.FreeTypeFont,
    size: tuple[int, int],
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
    size
        Canvas dimensions, normally from :func:`canvas_size`.

    Returns
    -------
    Image.Image
        The rendered RGB frame.
    """
    width, height = size
    img = Image.new("RGB", size, BG)
    d = ImageDraw.Draw(img)

    # Title bar with the three window dots.
    d.rectangle([0, 0, width, BAR_H], fill=CHROME)
    d.line([0, BAR_H, width, BAR_H], fill=BORDER, width=2)
    for i, colour in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
        cx = 30 + i * 26
        d.ellipse([cx - 8, BAR_H // 2 - 8, cx + 8, BAR_H // 2 + 8], fill=colour)
    d.text((CAPTION_X, BAR_H // 2 - FONT_SIZE // 2 - 2), caption, font=font_bold, fill=DIM)

    y = BAR_H + MARGIN_Y
    for line in lines:
        if line is not None:
            text, colour = line
            d.text((MARGIN_X, y), text, font=font, fill=colour)
        y += LINE_H

    d.rectangle([0, 0, width - 1, height - 1], outline=BORDER, width=2)
    return img


def main() -> None:
    """Render every frame and write it as an individual PNG."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    font, font_bold = _load_fonts()
    size = canvas_size(font, font_bold)

    for stem, (caption, lines) in zip(STEMS, FRAMES, strict=True):
        path = OUT_DIR / f"{stem}.png"
        render_frame(caption, lines, font, font_bold, size).save(path, optimize=True)
        print(f"{path.name:<34} {path.stat().st_size / 1024:>5.0f} KB")

    print(f"canvas   : {size[0]}×{size[1]}")


if __name__ == "__main__":
    main()
