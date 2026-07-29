"""Render the front-of-house view of the Red-phase block as an animated GIF.

This is the counterpart to ``render-backstage-frames.py``. Where those stills
show what the machinery emits, this animation shows what the *user* sees: a
task handed to the coordinator, a subagent that believes it is finished, a
hook that refuses the handoff, and a self-correction -- all inside the chat,
without a commit and without a human intervening.

Deliberately stylised rather than a pixel-imitation of any particular chat
client. It is a reconstruction and should be presented as one; a fake
screenshot would undermine the artefacts around it.

Content is synthetic: generic order/refund domain, no real project data.

Usage:
    python render-chat-loop.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------- appearance

# The width is measured from the content (see ``canvas_width``) rather than
# fixed, so the panel never carries dead space. The height follows from how
# many transcript lines stay visible before the panel scrolls.
VISIBLE_LINES = 20
MARGIN_X, MARGIN_Y = 46, 26
FONT_SIZE = 22
LINE_H = 30
BAR_H = 56
CAPTION_X = 124
CAPTION = "chat  \u2014  what the user sees"
INDENT = "   "
BAND_PAD = 18

BG = (13, 17, 23)
CHROME = (22, 27, 34)
BORDER = (48, 54, 61)
BAND = (45, 20, 24)

FG = (201, 209, 217)
DIM = (110, 118, 129)
GREEN = (63, 185, 80)
RED = (248, 81, 73)
YELLOW = (210, 153, 34)
BLUE = (88, 166, 255)
PURPLE = (188, 140, 255)
TEAL = (57, 197, 187)

FONT_PATH = r"C:\Windows\Fonts\consola.ttf"
FONT_BOLD_PATH = r"C:\Windows\Fonts\consolab.ttf"

OUT_DIR = Path(__file__).resolve().parent / "assets"
GIF_PATH = OUT_DIR / "chat-red-phase-loop.gif"
FALLBACK_PATH = OUT_DIR / "chat-red-phase-fallback.png"

MAX_LINES = VISIBLE_LINES
HEIGHT = BAR_H + 2 * MARGIN_Y + (VISIBLE_LINES - 1) * LINE_H + FONT_SIZE + 5
Rgb = tuple[int, int, int]
Line = tuple[str, Rgb]


@dataclass(frozen=True)
class Message:
    """One turn in the reconstructed chat transcript.

    Attributes
    ----------
    role
        Speaker label rendered in the header line.
    colour
        Accent colour for the header line.
    body
        Body lines as ``(text, rgb)`` pairs.
    highlight
        Whether to draw the message on a tinted band. Used for the hook
        interjection so it visibly interrupts the conversation.
    """

    role: str
    colour: Rgb
    body: list[Line]
    highlight: bool = False


# ------------------------------------------------------------------- content

USER = Message(
    "you",
    BLUE,
    [
        ("Implement REQ-114 \u2014 orders returned between 30 and 60 days", FG),
        ("after delivery get a 50% refund.", FG),
    ],
)

COORD_DISPATCH = Message(
    "coordinator",
    PURPLE,
    [
        ("Workflow: Full TDD   \u00b7   Tier: Standard   \u00b7   4 subtasks", FG),
        ("Branch:   agent/req-114-partial-refund-window", FG),
        ("\u2192 dispatching test-writer (Red phase)", YELLOW),
    ],
)

TW_THINKING = Message(
    "test-writer",
    TEAL,
    [("reading skills \u2026 writing tests for the 30\u201360 day window \u2026", DIM)],
)

TW_DONE = Message(
    "test-writer",
    TEAL,
    [
        ("Added 3 tests for the partial-refund window.", FG),
        ("$ pytest -q   \u2192   1 passed in 0.31s", GREEN),
        ("Gate Summary \u2014 HARD 3/3 passed, SOFT 2 evaluated", GREEN),
        ("Handing back to the coordinator.", GREEN),
    ],
)

HOOK = Message(
    # No pictographs in the label: Consolas Bold has no dingbat glyphs and
    # renders them as tofu. The band and the accent bar carry the alarm.
    "hook  \u00b7  test-writer : SubagentStop",
    RED,
    [
        ('decision: "block"   \u2014   Red-phase gate', RED),
        ("All tests PASS. New tests must FAIL against the existing", FG),
        ("production code to express a genuine requirement gap.", FG),
        ("", FG),
        ("Handoff refused. Back to test-writer \u2014 attempt 2 of 2.", FG),
    ],
    highlight=True,
)

TW_FIX = Message(
    "test-writer",
    TEAL,
    [
        ("The block is right. My test asserted what the code already", FG),
        ("does (0.00 after 30 days), not what REQ-114 asks for", FG),
        ("(50% between 30 and 60). Rewriting.", FG),
    ],
)

TW_RED = Message(
    "test-writer",
    TEAL,
    [
        ("$ pytest -q   \u2192   1 failed in 0.29s", RED),
        ("E   assert 0.00 == 50.00", RED),
        ("Failing for the requirement, not for a typo.", DIM),
        ("Gate Summary \u2014 HARD 3/3 passed", GREEN),
    ],
)

COORD_PROCEED = Message(
    "coordinator",
    PURPLE,
    [
        ("Red gate satisfied \u2192 dispatching implementer", FG),
        ("", FG),
        ("Nothing was committed. No human reviewed anything.", YELLOW),
        ("The correction happened inside the loop.", YELLOW),
    ],
)

# Cumulative transcript states. Frame 4 replaces the "thinking" turn with the
# finished one, exactly as a streaming chat client would.
FRAMES: list[list[Message]] = [
    [USER],
    [USER, COORD_DISPATCH],
    [USER, COORD_DISPATCH, TW_THINKING],
    [USER, COORD_DISPATCH, TW_DONE],
    [USER, COORD_DISPATCH, TW_DONE, HOOK],
    [USER, COORD_DISPATCH, TW_DONE, HOOK, TW_FIX],
    [USER, COORD_DISPATCH, TW_DONE, HOOK, TW_FIX, TW_RED],
    [USER, COORD_DISPATCH, TW_DONE, HOOK, TW_FIX, TW_RED, COORD_PROCEED],
]

# Per-frame duration in milliseconds. The block and the payoff are held
# longest; the "thinking" beat is deliberately brief.
DURATIONS = [2400, 3200, 1600, 3400, 4600, 3200, 3400, 4800]


def _load_fonts() -> tuple[ImageFont.FreeTypeFont, ImageFont.FreeTypeFont]:
    """Load the monospace faces, falling back to the regular one if needed."""
    regular = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    try:
        bold = ImageFont.truetype(FONT_BOLD_PATH, FONT_SIZE)
    except OSError:
        bold = regular
    return regular, bold


def flatten(messages: list[Message]) -> list[tuple[str, Rgb, bool, bool]]:
    """Expand messages into drawable lines.

    Parameters
    ----------
    messages
        The transcript state to render.

    Returns
    -------
    list of (text, colour, is_header, highlighted)
        One entry per rendered line, including the blank separator after each
        message. Header lines carry the role label; body lines are indented.
    """
    out: list[tuple[str, Rgb, bool, bool]] = []
    for msg in messages:
        out.append((msg.role, msg.colour, True, msg.highlight))
        for text, colour in msg.body:
            out.append((INDENT + text if text else "", colour, False, msg.highlight))
        out.append(("", FG, False, False))
    return out


def canvas_width(
    font: ImageFont.FreeTypeFont,
    font_bold: ImageFont.FreeTypeFont,
) -> int:
    """Measure the narrowest width that fits every transcript state.

    All frames share one width, otherwise the GIF would jitter between frames.

    Parameters
    ----------
    font, font_bold
        Monospace faces used for body and header text.

    Returns
    -------
    int
        Pixel width including margins, the highlight band padding and the
        title-bar caption.
    """
    text_w = 0.0
    for state in FRAMES:
        for text, _, is_header, _ in flatten(state):
            text_w = max(text_w, (font_bold if is_header else font).getlength(text))

    return round(
        max(
            2 * MARGIN_X + text_w + BAND_PAD,
            CAPTION_X + font_bold.getlength(CAPTION) + MARGIN_X,
        )
    )


def render_frame(
    messages: list[Message],
    font: ImageFont.FreeTypeFont,
    font_bold: ImageFont.FreeTypeFont,
    width: int,
) -> Image.Image:
    """Render one transcript state as a chat panel.

    The transcript is bottom-aligned and clipped to the most recent
    ``MAX_LINES`` lines, so long conversations scroll the way a real client
    would rather than shrinking the text.

    Parameters
    ----------
    messages
        Transcript state to draw.
    font, font_bold
        Monospace faces for body and header lines.
    width
        Canvas width, normally from :func:`canvas_width`.

    Returns
    -------
    Image.Image
        The rendered RGB frame.
    """
    img = Image.new("RGB", (width, HEIGHT), BG)
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, width, BAR_H], fill=CHROME)
    d.line([0, BAR_H, width, BAR_H], fill=BORDER, width=2)
    for i, colour in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
        cx = 30 + i * 26
        d.ellipse([cx - 8, BAR_H // 2 - 8, cx + 8, BAR_H // 2 + 8], fill=colour)
    d.text(
        (CAPTION_X, BAR_H // 2 - FONT_SIZE // 2 - 2),
        CAPTION,
        font=font_bold,
        fill=DIM,
    )

    lines = flatten(messages)[-MAX_LINES:]
    top = BAR_H + MARGIN_Y

    # Bands first, so text never sits under a fill.
    for i, (_, _, _, highlighted) in enumerate(lines):
        if not highlighted:
            continue
        y = top + i * LINE_H
        left, right = MARGIN_X - BAND_PAD, width - MARGIN_X + BAND_PAD
        d.rectangle([left, y - 5, right, y + LINE_H - 5], fill=BAND)
        d.rectangle([left, y - 5, left + 4, y + LINE_H - 5], fill=RED)

    for i, (text, colour, is_header, _) in enumerate(lines):
        if not text:
            continue
        y = top + i * LINE_H
        d.text((MARGIN_X, y), text, font=font_bold if is_header else font, fill=colour)

    d.rectangle([0, 0, width - 1, HEIGHT - 1], outline=BORDER, width=2)
    return img


def main() -> None:
    """Render the transcript states and write the GIF and a fallback still."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    font, font_bold = _load_fonts()
    width = canvas_width(font, font_bold)

    frames = [render_frame(state, font, font_bold, width) for state in FRAMES]
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

    # Frame 5 (index 4) is the turn: the hook refusing a green handoff.
    frames[4].save(FALLBACK_PATH, optimize=True)

    print(f"GIF      : {GIF_PATH.name}  ({GIF_PATH.stat().st_size / 1024:.0f} KB)")
    print(f"fallback : {FALLBACK_PATH.name}  ({FALLBACK_PATH.stat().st_size / 1024:.0f} KB)")
    print(f"duration : {sum(DURATIONS) / 1000:.1f} s over {len(frames)} frames")
    print(f"canvas   : {width}×{HEIGHT}, {MAX_LINES} visible lines")


if __name__ == "__main__":
    main()
