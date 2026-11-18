"""Add Thai to the PDF font (assets/fonts/NotoSansPdf-{Regular,Bold}.ttf).

The PDF library (Syncfusion) draws glyphs straight from the font's cmap and
ignores its layout tables, so Thai marks are never moved by the font's own
positioning rules. Two cases then collide:

  * a tone mark over an upper vowel, as in ที่: both sit at the same height,
    so the tone mark disappears into the vowel;
  * an upper vowel or tone mark over a tall consonant (ป ฝ ฟ ฬ): it runs into
    the consonant's tall stroke.

Legacy Thai fonts solved this the same way, before OpenType: extra copies of
the marks, raised or moved left, at private-use code points, with the text
switched to them where needed. This script adds those copies, and
lib/services/pdf_brand.dart (thaiForPdf) does the switching.

Usage, from mobile/ (needs fontTools):
  python3 tool/pdf_font/add_thai.py <base-dir> <thai-dir> <out-dir>

  <base-dir>  NotoSansPdf-Regular.ttf and -Bold.ttf without Thai
  <thai-dir>  NotoSansThai-400.ttf and -700.ttf (static Noto Sans Thai)
  <out-dir>   where the merged fonts are written
"""

import sys

from fontTools import subset
from fontTools.merge import Merger
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

# How far the copies move, in font units (the em is 1000). Tone marks start
# where upper vowels start (y 635) and the tallest upper vowel ends at 800,
# so a raised tone mark clears it by about 40. The tall consonants' stroke
# reaches about 140 units into where an upper mark sits.
RAISE = 205
LEFT = -140

UPPER_VOWELS = [0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37, 0x0E47]
TONES = [0x0E48, 0x0E49, 0x0E4A, 0x0E4B, 0x0E4C]
NIKHAHIT = 0x0E4D

# Private-use code points for the copies. Must match pdf_brand.dart.
PUA_TONE_RAISED = 0xF70A          # + index in TONES
PUA_TONE_LEFT = 0xF705            # + index in TONES
PUA_TONE_RAISED_LEFT = 0xF700     # + index in TONES
PUA_UPPER_LEFT = 0xF710           # + index in UPPER_VOWELS
PUA_NIKHAHIT_LEFT = 0xF716


def add_copy(font, source_cp, new_cp, dx, dy):
    cmap = font.getBestCmap()
    src = cmap[source_cp]
    name = f'{src}.pua{new_cp:04X}'
    glyf = font['glyf']
    pen = TTGlyphPen(font.getGlyphSet())
    glyf[src].draw(TransformPen(pen, (1, 0, 0, 1, dx, dy)), glyf)
    glyph = pen.glyph()
    glyph.recalcBounds(glyf)
    font.setGlyphOrder(font.getGlyphOrder() + [name])
    glyf[name] = glyph
    adv, _ = font['hmtx'][src]
    font['hmtx'][name] = (adv, getattr(glyph, 'xMin', 0))
    for table in font['cmap'].tables:
        if table.isUnicode():
            table.cmap[new_cp] = name


def main(base_dir, thai_dir, out_dir):
    for style, weight in (('Regular', 400), ('Bold', 700)):
        base_path = f'{base_dir}/NotoSansPdf-{style}.ttf'
        thai = TTFont(f'{thai_dir}/NotoSansThai-{weight}.ttf')
        opts = subset.Options()
        opts.layout_features = []
        opts.hinting = False
        opts.drop_tables += ['GSUB', 'GPOS', 'GDEF', 'STAT']
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=range(0x0E00, 0x0E80))
        sub.subset(thai)
        thai_path = f'{out_dir}/thai-{style}.ttf'
        thai.save(thai_path)

        base = TTFont(base_path)
        merged = Merger().merge([base_path, thai_path])
        # The original identity and line metrics, so PDFs lay out as before.
        merged['name'] = base['name']
        for a in ('ascent', 'descent', 'lineGap'):
            setattr(merged['hhea'], a, getattr(base['hhea'], a))
        for a in ('sTypoAscender', 'sTypoDescender', 'sTypoLineGap', 'usWinAscent', 'usWinDescent', 'usWeightClass'):
            setattr(merged['OS/2'], a, getattr(base['OS/2'], a))

        for i, cp in enumerate(TONES):
            add_copy(merged, cp, PUA_TONE_RAISED + i, 0, RAISE)
            add_copy(merged, cp, PUA_TONE_LEFT + i, LEFT, 0)
            add_copy(merged, cp, PUA_TONE_RAISED_LEFT + i, LEFT, RAISE)
        for i, cp in enumerate(UPPER_VOWELS):
            add_copy(merged, cp, PUA_UPPER_LEFT + i, LEFT, 0)
        add_copy(merged, NIKHAHIT, PUA_NIKHAHIT_LEFT, LEFT, 0)

        out = f'{out_dir}/NotoSansPdf-{style}.ttf'
        merged.save(out)
        print(out, len(merged.getGlyphOrder()), 'glyphs')


if __name__ == '__main__':
    main(*sys.argv[1:4])
