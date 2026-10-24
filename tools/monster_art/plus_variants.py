#!/usr/bin/env python3
"""Make *_plus variants from the new base sheets: hue-shifted palette + gold elite outline (dark line just inside)."""
import colorsys, os, shutil, sys
from PIL import Image
GOLD=(255,200,48)
HUE=0.42; SAT=1.12; VAL=0.96
def shift(px):
    r,g,b,a=px
    h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
    if s<0.12: return (r,g,b,a)                       # keep greys/whites (metal, eye glints)
    h=(h+HUE)%1; s=min(1,s*SAT); v=v*VAL
    r,g,b=colorsys.hsv_to_rgb(h,s,v); return (int(r*255),int(g*255),int(b*255),a)
def plusify_cell(cell):
    w,h=cell.size; src=cell.load(); out=cell.copy(); op=out.load()
    for y in range(h):
        for x in range(w):
            if src[x,y][3]: op[x,y]=shift(src[x,y])
    def opaque(x,y): return 0<=x<w and 0<=y<h and src[x,y][3]>0
    ring1=set()
    for y in range(h):
        for x in range(w):
            if src[x,y][3] and any(not opaque(x+dx,y+dy) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1))): ring1.add((x,y))
    for (x,y) in ring1: op[x,y]=(*GOLD,255)
    for y in range(h):
        for x in range(w):
            if src[x,y][3] and (x,y) not in ring1 and any((x+dx,y+dy) in ring1 for dx,dy in ((1,0),(-1,0),(0,1),(0,-1))):
                r,g,b,a=op[x,y]; op[x,y]=(int(r*0.35),int(g*0.35),int(b*0.35),a)
    return out
def plusify(sheet, fw):
    out=Image.new("RGBA",sheet.size,(0,0,0,0))
    for r in range(2):
        for c in range(4):
            cell=sheet.crop((c*fw,r*fw,c*fw+fw,r*fw+fw)); out.alpha_composite(plusify_cell(cell),(c*fw,r*fw))
    return out
GROUND=["slime","beetle","spider","crab","crawler","pillbug","tortoise","urchin","mole","scarab","tick","slug","jelly","armadillo","roller"]
FLIERS=["bat","wasp","moth","hornet","dragonfly","firefly","hoverbot","propeller","stingray","sky_jelly"]
BOSSES=["colossus_v2","iron_maw_v2","juggernaut_v2","leviathan_v2","overseer_v2"]
def jobs(root):
    for n in GROUND: yield (f"{root}/ground/{n}/{n}_ground_sheet.png", f"{n}_plus", "ground", 40)
    for n in FLIERS: yield (f"{root}/flier/{n}/{n}_flier_sheet.png", f"{n}_plus", "flier", 40)
    for n in BOSSES: yield (f"{root}/boss/{n}/{n}_boss_sheet.png", n.replace("_v2","_plus_v2"), "boss", 80)
if __name__=="__main__":
    root, out, orig = sys.argv[1], sys.argv[2], sys.argv[3]
    for src,pid,kind,fw in jobs(root):
        sh=Image.open(src).convert("RGBA"); p=plusify(sh,fw)
        d=os.path.join(out,pid); os.makedirs(d,exist_ok=True); p.save(os.path.join(d,f"{pid}_{kind}_sheet.png"),optimize=True)
        j=os.path.join(orig,pid,f"{pid}_{kind}_frames.json")
        if os.path.exists(j): shutil.copy(j,os.path.join(d,f"{pid}_{kind}_frames.json"))
        else: print("no json for",pid)
    print("built plus variants")
