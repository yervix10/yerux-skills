# Palette

An executable skill that turns hex colors into complete color palettes and delivers them as a
variables file ready to import into _Figma_, together with the RGB, CMYK and HSL values of each
original color.

Unlike a reference catalog split into a `rules/` directory, this is a procedural skill: a small
set of linear operations that are read in full and executed in order, backed by one deterministic
script. Its structure is intentionally flat.

## Structure

- `SKILL.md` - The skill definition. Contains the execution protocol, the JSON structure, and the
  directives that govern behavior.
- `metadata.json` - Document metadata (version, author, date, abstract, references)
- `scripts/generate_palette.py` - The generator. Pure _Python 3_, no dependencies.

## What it does

The skill exposes three operations.

**Operation A — Generate a Palette (default)**

1. **Identifies the colors** - every hex in the message, with or without `#`, 3 or 6 digits,
   optionally named (`Primary: #E43636`). Unnamed colors become _Primary_, _Secondary_,
   _Tertiary_… in order.
2. **Generates the file** - runs the script, which builds the 11 shades (50 to 950) of each color
   plus a `DEFAULT` entry (an alias to the shade where the original color landed), and writes `Value.json` in the _Figma_ variables format.
3. **Delivers both things together** - the file, and in the chat the RGB, CMYK and HSL values of
   each original color:

```
default: #E43636
RGB: (228, 54, 54)
CMYK: (0%, 76.32%, 76.32%, 10.59%)
HSL: (0, 76.32%, 55.29%)
```

It never asks for a name: the file name is fixed and the color names default to the ordinal
scheme above.

**Operation B — Get Color Values Only**

When the user asks for just the RGB, CMYK and HSL values, `--format info` prints the block above
for the original color of each hex, without creating a file.

**Operation C — Other Formats**

On explicit request, the same palette can be printed as plain text, CSS (`@theme` variables),
_Tailwind_ config, or simple JSON with `--format text|css|tailwind|json`. No file is created.

## How the shades are computed

The algorithm is the same one used by _hue_, ported to Python,
so the shades match its hexadecimal values exactly.

- The input color is matched to the closest _Tailwind_ color family (red, orange, ... stone, plus
  _Yellow Mud_ and _Mud_) by _CIEDE2000_ distance. Gray families are only candidates for
  low-saturation inputs (HSL saturation of 0.15 or less), and chromatic families for the rest.
- In that family, the shade whose HSL lightness is closest to the input becomes the input color,
  saved **exactly** as `default`. The rest of the family is re-tinted with the same hue offset and
  saturation ratio.
- `--base` uses hue's "lock input color" mode: the whole scale is re-anchored so the input color
  lands at the chosen shade.
- Verified against hue's own code on more than 600 colors (automatic mode) and on five base shades
  (lock mode): identical hexadecimal values.

## Output format

One group per color, with `DEFAULT` first (alias, e.g. `{Primary.800}`) and then its 11 shades, plus a separate `Tailwind` group
holding `White` and `Black`, and the mode name at the end:

```
Tailwind: { White, Black }
<Name>:   { DEFAULT, 50, 100, ... 950 }
$extensions: { com.figma.modeName: "Value" }
```

Each variable is a _DTCG_ color token (`$type`, `$value` with `colorSpace`, `components`, `alpha`
and `hex`) with the `ALL_SCOPES` extension. `com.figma.variableId` is left out on purpose: _Figma_
creates new variables, with no risk of overwriting existing variables from another file.

### Importing into Figma

1. Open the Variables view and create a new collection.
2. Rename the collection (_Figma_ calls it "Collection 1" by default).
3. Drag `Value.json` onto the Variables view.

### Known Figma limitations

- **The collection name cannot be set from the JSON.** The native import format has no field for
  it; it is the name of the collection created in the Variables view.
- **The values column takes its name from the file name**, which is why the file is called
  `Value.json`. The `modeName` inside the JSON is ignored on import.
- **`DEFAULT` is listed last** after importing, because JavaScript orders numeric keys (50, 100…)
  before text keys. This cannot be fixed from the JSON.

## Usage

The skill is triggered by plain language (`palette for #E43636 and #4A90E2`) and runs the script
internally. The script can also be used directly:

```bash
generate_palette.py E43636 4A90E2                      # Value.json + values of each default
generate_palette.py Primary=E43636 Secondary=4A90E2    # same, with names
generate_palette.py F9AE00 --format info               # RGB, CMYK and HSL only
generate_palette.py F9AE00 --format css                # CSS variables (also: tailwind, text, json)
```

Options: `--filename` (file name), `--out-dir` (output folder), `--no-bw` (skip `White` and `Black`),
`--bw-group` (rename the `Tailwind` group), `--base` (force the shade of the original color),
`--mode` (mode name inside the JSON).

## Behavior configuration

The skill's behavior is defined by the directives section of `SKILL.md`:

1. **No names are asked** - neither for the file nor for the colors; defaults are applied silently.
2. **Fixed file name** - always `Value.json`, unless the user explicitly asks for another one.
3. **Always both deliverables** - the file and the RGB, CMYK and HSL values travel together in the
   same reply.
4. **Values are the original color's** - the printed values describe `default`, not every shade.
5. **`DEFAULT` leads each group** - an alias to the shade holding the exact original color, before the 11 shades.
6. **`White` and `Black` live in their own group** - `Tailwind`, never loose at the root.
7. **The shade is chosen automatically** - by lightness, unless the user forces one.
8. **The JSON is never pasted in the chat** - it is delivered as a file.

To change how the skill behaves, edit these directives — not the execution protocol.

## Scope

This skill currently covers palette generation (_Operation A_), color values (_Operation B_), and
alternative text formats (_Operation C_). If it grows further (several modes such as light and
dark, other token types), keep splitting it **by operation**, not into a `rules/` catalog.

## Acknowledgments

Created by Yerson Vizcaino.
