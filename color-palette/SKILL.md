---
name: color-palette
description: 'Generates color palettes of 11 shades in the Tailwind style from one or more hex codes, delivered as a variables JSON ready to import into Figma (with a `DEFAULT` entry that is an alias to the shade holding the original color), together with the RGB, CMYK and HSL values of each color. Use it whenever the user passes one or more hex codes (for example F9AE00, #E43636 or "Primary: 4A90E2") and wants a color palette, shades, a Tailwind-style scale, a Figma variables file, or the RGB, CMYK and HSL values of a color. Also use it for requests such as "generate a palette", "create the shades of this color" or "paleta de colores".'
---

# Palette: hex colors → Figma JSON

Given one or more hex colors, generate for each one a scale of 11 shades plus a `DEFAULT` entry that references (alias, like `{Primary.800}`) the shade where the exact original color landed, and save it as a `.json` file in Figma's variables format, ready to import. **Always deliver both things in the same reply**: the file, and the RGB, CMYK and HSL values of each original color (`default`).

## Workflow

### 1. Identify the colors
Take every hex in the message (with or without `#`, 3 or 6 digits). The user may name them: `Primary: #E43636`, `Secondary = 4A90E2`. Unnamed colors are called **Primary, Secondary, Tertiary…** by the script, in order.

### 2. File name (do not ask)
**Do not ask the user for any name.** The file is always called `Value.json`: when importing, Figma takes the header of the values column from the file name. Only if the user explicitly asks for a different file name, pass it with `--filename`.

The collection name cannot be set from the JSON: Figma's native format has no field for it. It is the name of the collection the user creates in the Variables view before dragging the file in (Figma calls it "Collection 1" by default).

### 3. Generate
Do not compute the shades by eye: use the script, which is deterministic and a port of the generator used by hue, so the hexadecimal values are the same as in hue.

```bash
python /mnt/skills/user/palette/scripts/generate_palette.py Primary=E43636 Secondary=4A90E2 \
  --out-dir /mnt/user-data/outputs            # creates Value.json; use --filename only if the user asks for another name
```

(If the skill lives elsewhere, use the location of this SKILL.md.) The script creates `Value.json` and prints to stdout a `FILE: <path>` line followed by the RGB, CMYK and HSL values of each color's `default` (with a `## Name` title when there are several colors). On stderr it reports which shade each color landed on.

Useful options:
- `--no-bw` leaves out the `White` and `Black` variables, which are included by default inside a separate group called `Tailwind`.
- `--bw-group "Other"` renames that group.
- `--mode` mode name inside the JSON (default `Value`). Figma ignores it on import and uses the file name; the names column is always `Name`.
- `--base 500` forces the shade where the user's color lands. By default it is automatic: the color is placed at the shade whose lightness fits best (a vivid yellow lands at 500, a mid red at 600, a mid blue at 500, a navy blue at 950).

### 4. Deliver (always both things)
1. Present `Value.json` with `present_files`.
2. In the chat, paste the RGB, CMYK and HSL values the script printed, inside a code block and without reformatting. Like this:

```
default: #E43636
RGB: (228, 54, 54)
CMYK: (0%, 76.32%, 76.32%, 10.59%)
HSL: (0, 76.32%, 55.29%)
```

3. Do not list or print the 11 shades (neither their numbers nor their hex values) in the chat; just state that the file contains them. At most one line at the end: which shade each color landed on, and that the variables are imported from Figma's Variables panel. Do not paste the full JSON in the chat.

## JSON structure

One group per color with `DEFAULT` first and then its 11 shades, plus a `Tailwind` group with `White` and `Black` at the start, and the mode at the end:

```
Tailwind: { White, Black }                          ← separate group, not loose at the root
<Name>: { "DEFAULT", + its 11 shades }            ← DEFAULT = alias "{Name.<shade>}" to the shade holding the exact original color
$extensions: { "com.figma.modeName": "Value" }
```

Each variable is `{"$type":"color","$value":{"colorSpace":"srgb","components":[r,g,b],"alpha":1,"hex":"#RRGGBB"},"$extensions":{"com.figma.scopes":["ALL_SCOPES"]}}`. `com.figma.variableId` is left out on purpose: Figma creates new variables, with no risk of overwriting existing variables from another file.

Note: `DEFAULT` is not a copy of the hex: it is a Figma alias (`"$value": "{Name.800}"`), the same way Figma exports it natively. In `--format css` it becomes `--color-name: var(--color-name-800);`. Figma lists `DEFAULT` last when importing, because JavaScript always orders numeric keys (50, 100…) before text keys. This cannot be fixed from the JSON.

How to import into Figma: open the Variables view, create a new collection and rename it, then drag `Value.json` onto the Variables view.

## Only the RGB, CMYK and HSL values (`--format info`)

If the user asks for **only** the RGB, CMYK and HSL values (no JSON), use `--format info`: it prints just the original color (`default`) of each color, without creating a file.

```bash
python /mnt/skills/user/palette/scripts/generate_palette.py F9AE00 --format info
```

## Other formats (only if the user asks for them)

If the user explicitly asks for text, CSS, Tailwind or plain JSON instead of Figma, use `--format text|css|tailwind|json` (no file is created). In `text` and similar formats the first line is `default: #HEX`. With several colors it prints one block per color with its title.

## Special cases

- **Hex without `#` or with 3 digits** (`F90`): the script accepts it and expands it.
- **Invalid hex**: tell the user the expected format and ask for the value again.
- **Color name instead of hex** ("blue"): ask for the hex, or suggest one and confirm before generating.
- **Repeated names**: the script stops; ask the user to change one.
- **More than 10 unnamed colors**: they are named `Color 11`, `Color 12`… Suggest naming them.
- **Near-gray colors**: they are matched against the gray families (Slate, Gray, Zinc, Stone), as hue does.
- **The shades are an approximation**: the original color is always exact; the other shades are the same ones hue produces, and may differ from other tools. If the user wants to adjust one, edit it by hand in the JSON or in Figma.
