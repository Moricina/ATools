#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
prepare_milky_panels.py
为 ATools 悬浮面板（搜索框收拢/展开/辅助工具/暂存架）注入半透明乳白色毛玻璃底板：
- 严格仅在真实圆角卡片内部填充半透明白色（RGB 246, 246, 247, alpha 0.92）；
- 卡片外部四周的原生透明留白区域保持 100% 透明；
- 绝不在卡片外围产生任何多余的白色矩形框或底衬，完全贴合软件界面轮廓。
"""

import os
from PIL import Image, ImageDraw

PANELS = [
    ("/tmp/shelf_preview.png", "/tmp/shelf_preview_milky.png", 18),
    ("/tmp/shelf_vertical_preview.png", "/tmp/shelf_vertical_preview_milky.png", 18),
    ("/tmp/search_collapsed_preview.png", "/tmp/search_collapsed_preview_milky.png", 14),
    ("/tmp/search_expanded_preview.png", "/tmp/search_expanded_preview_milky.png", 18),
    ("/tmp/search_syntax_selection_preview.png", "/tmp/search_syntax_selection_preview_milky.png", 18),
    ("/tmp/search_capsule_preview.png", "/tmp/search_capsule_preview_milky.png", 18),
    ("/tmp/search_autopaste_preview.png", "/tmp/search_autopaste_preview_milky.png", 18),
    ("/tmp/search_calc_preview.png", "/tmp/search_calc_preview_milky.png", 18),
    ("/tmp/search_dict_preview.png", "/tmp/search_dict_preview_milky.png", 18),
    ("/tmp/search_sys_preview.png", "/tmp/search_sys_preview_milky.png", 18),
]

def process_file(src, dst, corner_radius):
    if not os.path.exists(src):
        print(f"Warning: {src} not found")
        return
        
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    pixels = im.load()
    
    # 查找非全透明像素的实际边界
    min_x, max_x, min_y, max_y = w, 0, h, 0
    for y in range(h):
        for x in range(w):
            if pixels[x, y][3] > 18:
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
                
    if min_x >= max_x or min_y >= max_y:
        im.save(dst)
        return
        
    pad = 2
    box = [min_x + pad, min_y + pad, max_x - pad, max_y - pad]
    
    bg_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(bg_layer)
    
    # 半透明乳白底色 (RGB: 246, 246, 247, 92% 不透明度)
    draw.rounded_rectangle(box, radius=corner_radius, fill=(246, 246, 247, int(255 * 0.92)))
    # 极细白色高光内描边
    draw.rounded_rectangle(box, radius=corner_radius, outline=(255, 255, 255, 180), width=1)
    
    # 复合
    res = Image.alpha_composite(bg_layer, im)
    res.save(dst)
    print(f"✓ Created milky panel: {dst} (bbox: {min_x},{min_y} -> {max_x},{max_y})")

def main():
    print("==> Processing panels for translucent milky white glass...")
    for src, dst, radius in PANELS:
        process_file(src, dst, radius)
    print("✅ All floating panels processed with exact milky white background!")

if __name__ == "__main__":
    main()
