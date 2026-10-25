"""Render recorded Lua page geometry with desktop fonts; not native KOReader QA."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'test-results' / 'feedback-previews'


def render(preview, regular, bold):
    canvas = Image.new('RGBA', (preview['width'], preview['height']), 'white')
    for op in preview['operations']:
        layer = Image.new('RGBA', canvas.size)
        draw = ImageDraw.Draw(layer)
        x, y, w, h = (op[k] for k in ('x', 'y', 'w', 'h'))
        if w <= 0 or h <= 0:
            continue
        if op['kind'] == 'rect':
            color = int(op['color'])
            draw.rectangle((x, y, x+w-1, y+h-1), fill=(color, color, color, 255))
        elif op['kind'] == 'text':
            font = ImageFont.truetype(str(bold if op['bold'] else regular), max(1, round(op['size'])))
            text = op['text']
            if draw.textlength(text, font=font) > w:
                while text and draw.textlength(text+'…', font=font) > w:
                    text = text[:-1]
                text += '…'
            box = draw.textbbox((0, 0), text, font=font, anchor='lt')
            tw, th = box[2]-box[0], box[3]-box[1]
            px = x if op['align'] == 'left' else x+w-tw if op['align'] == 'right' else x+(w-tw)/2
            color = int(op['color'])
            draw.text((px, y+(h-th)/2), text, font=font, fill=(color, color, color, 255), anchor='lt')
        else:
            cx, cy, size = x+w/2, y+h/2, op['size']
            pen = max(1, round(size/12))
            if op['name'] == 'close':
                r = size*.28
                draw.line((cx-r, cy-r, cx+r, cy+r), fill='black', width=pen)
                draw.line((cx-r, cy+r, cx+r, cy-r), fill='black', width=pen)
            elif op['name'] == 'info':
                r = size*.37
                draw.ellipse((cx-r, cy-r, cx+r, cy+r), outline='black', width=pen)
                draw.line((cx, cy, cx, cy+r*.6), fill='black', width=pen)
                draw.ellipse((cx-pen/2, cy-r*.6, cx+pen/2, cy-r*.6+pen), fill='black')
            else:
                r = size*.25
                if 'up' in op['name']:
                    points = (cx-r, cy+r/2, cx, cy-r/2, cx+r, cy+r/2)
                elif 'down' in op['name']:
                    points = (cx-r, cy-r/2, cx, cy+r/2, cx+r, cy-r/2)
                else:
                    points = (cx+r/2, cy-r, cx-r/2, cy, cx+r/2, cy+r)
                draw.line(points, fill='black', width=pen)
        if op.get('clip'):
            c = op['clip']
            box = tuple(round(v) for v in (c['x'], c['y'], c['x']+c['w'], c['y']+c['h']))
            cropped = layer.crop(box)
            canvas.alpha_composite(cropped, dest=(box[0], box[1]))
        else:
            canvas = Image.alpha_composite(canvas, layer)
    return canvas.convert('RGB')


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--font', type=Path, default=Path('C:/Windows/Fonts/msyh.ttc'))
    parser.add_argument('--bold-font', type=Path, default=Path('C:/Windows/Fonts/msyhbd.ttc'))
    args = parser.parse_args()
    data = json.loads((ROOT/'test-results/portable/feedback-summary.json').read_text(encoding='utf-8'))
    OUT.mkdir(parents=True, exist_ok=True)
    for preview in data['previews']:
        target = OUT/(preview['name']+'.png')
        render(preview, args.font, args.bold_font).save(target)
        print(target)


if __name__ == '__main__':
    main()
