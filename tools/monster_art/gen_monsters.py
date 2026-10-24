#!/usr/bin/env python3
"""Procedural top-down (facing UP) monster sheets, 160x120 (4x3 cells of 40px).
Row0 walk(4)  Row1 death(4)  Row2 attack(0, left blank like the current sheets)."""
import json, math, os, shutil, sys
from PIL import Image, ImageDraw

K = 8                      # supersample factor
N = 40
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
ORIG = sys.argv[2] if len(sys.argv) > 2 else None   # existing assets/sprites (for frames json)

class Canvas:
    def __init__(s):
        s.im = Image.new("RGBA", (N*K, N*K), (0,0,0,0)); s.d = ImageDraw.Draw(s.im)
    def P(s, pts): return [(x*K, y*K) for x, y in pts]
    def ell(s, cx, cy, rx, ry, c): s.d.ellipse([(cx-rx)*K,(cy-ry)*K,(cx+rx)*K,(cy+ry)*K], fill=c)
    def poly(s, pts, c): s.d.polygon(s.P(pts), fill=c)
    def line(s, a, b, w, c): s.d.line(s.P([a, b]), fill=c, width=max(1,int(w*K)))
    def poly_line(s, pts, w, c): s.d.line(s.P(pts), fill=c, width=max(1,int(w*K)), joint="curve")

def finalize(cv, palette, outline):
    small = cv.im.resize((N, N), Image.BOX)
    px = small.load(); out = Image.new("RGBA", (N, N), (0,0,0,0)); op = out.load()
    for y in range(N):
        for x in range(N):
            r,g,b,a = px[x,y]
            if a < 110: continue
            best = min(palette, key=lambda p: (p[0]-r)**2+(p[1]-g)**2+(p[2]-b)**2)
            op[x,y] = (*best, 255)
    # 1px outline
    res = out.copy(); rp = res.load()
    for y in range(N):
        for x in range(N):
            if op[x,y][3] == 0:
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    xx,yy = x+dx,y+dy
                    if 0<=xx<N and 0<=yy<N and op[xx,yy][3]:
                        rp[x,y] = (*outline,255); break
    return res

def swing(t, phase=0.0): return math.sin((t/4.0 + phase) * 2*math.pi)

# ---------------------------------------------------------------- SLIME
def slime(t):
    c = Canvas(); s = [1.0,1.09,1.0,0.91][t]
    dk=(24,92,60); md=(60,190,110); lt=(130,235,150); hi=(225,255,225)
    c.ell(20,22,12.5*s,11.5/s,dk); c.ell(20,21,11*s,10*(1/s),md)
    c.ell(12,26,4,3.4,md); c.ell(29,27,4.5,3.6,md)          # side lobes -> not a perfect circle
    c.ell(15,17.5,5.5*s,3.2,lt); c.ell(13.2,16.2,2.2,1.3,hi)
    c.ell(24.5,26,5,3.2,(40,150,92))                         # nucleus
    for i,(bx,by) in enumerate([(26,17),(14,25),(23,30),(30,22)]):
        o = (t+i) % 4; c.ell(bx, by-o*0.4, 1.3, 1.3, lt)
    c.ell(16.5,13.2,2.0,2.2,(255,255,255)); c.ell(23.5,13.2,2.0,2.2,(255,255,255))
    c.ell(16.5,13.0,0.9,1.2,(20,40,30)); c.ell(23.5,13.0,0.9,1.2,(20,40,30))
    return c, [dk,md,lt,hi,(40,150,92),(255,255,255),(20,40,30)], (14,40,30)

# ---------------------------------------------------------------- BEETLE (rhino)
def beetle(t):
    c = Canvas(); body=(176,58,36); dk=(112,34,26); lt=(225,110,70); leg=(52,30,24); horn=(232,200,130)
    for i,(y0,reach) in enumerate([(15,-4),(20,0),(25,4)]):
        for sd in (-1,1):
            ph = swing(t, 0.5*((i+(0 if sd<0 else 1))%2)); dy = ph*2.2
            c.poly_line([(20+sd*4,y0),(20+sd*9,y0+reach*0.4+dy),(20+sd*13,y0+reach+dy*1.4)],1.5,leg)
    c.ell(20,27,9,10.5,dk); c.ell(20,26,8,9.5,body)                       # elytra
    c.line((20,17),(20,36),0.8,dk)                                         # shell split
    c.ell(16,22,3,5,lt); c.ell(25,30,2.4,3,dk)
    c.ell(20,15,5.6,4.4,(70,40,32)); c.ell(20,14.5,4.6,3.4,(105,62,46))    # thorax
    c.ell(20,10.5,3.4,3.2,(80,48,36))                                      # head
    c.poly([(19,9),(21,9),(21.3,4),(19.7,3),(18.7,4)],horn)                # horn stem
    c.poly([(18.6,4.2),(21.4,4.2),(24.5,0.8),(22.6,0.4),(20,2.4),(17.4,0.4),(15.5,0.8)],horn)
    c.ell(18,10,0.9,0.9,(255,230,120)); c.ell(22,10,0.9,0.9,(255,230,120))
    return c, [dk,body,lt,leg,horn,(70,40,32),(105,62,46),(80,48,36),(255,230,120)], (24,12,10)

# ---------------------------------------------------------------- SPIDER
def spider(t):
    c = Canvas(); leg=(58,34,96); legl=(108,70,160); ab=(78,44,120); abl=(120,76,170); th=(98,60,144)
    legs=[(-1,13,-9,-9),(-1,16,-13,-3),(-1,19,-13,4),(-1,22,-9,11)]
    for sd in (-1,1):
        for i,(_,y0,dx,dy) in enumerate(legs):
            ph = swing(t, 0.5*((i+(0 if sd<0 else 1))%2))*1.8
            kx, ky = 20+sd*7, y0-4.5 + ph*0.5
            fx, fy = 20+sd*(abs(dx)+4.2), y0+dy*0.55+ph
            c.poly_line([(20+sd*3.5,y0),(kx,ky),(fx,fy)],1.4,leg)
            c.line((kx,ky),(fx,fy),0.5,legl)
    c.ell(20,27,7.2,9.6,ab); c.ell(18,24,3.6,5,abl)
    c.poly([(20,22),(22.4,26),(20,30),(17.6,26)],(232,60,52))               # marking
    c.ell(20,15,5.2,5,th); c.ell(20,12.2,3.2,2.6,(128,90,170))
    for ex,ey in ((18.2,11),(21.8,11),(19,9.6),(21,9.6)): c.ell(ex,ey,0.75,0.75,(255,236,110))
    return c, [leg,legl,ab,abl,th,(232,60,52),(128,90,170),(255,236,110)], (22,12,36)

# ---------------------------------------------------------------- CRAB
def crab(t):
    c = Canvas(); sh=(214,84,48); dk=(140,44,34); lt=(250,150,92); cl=(244,112,60); tip=(255,232,200)
    for sd in (-1,1):
        for i in range(3):
            ph = swing(t, 0.5*((i+(0 if sd<0 else 1))%2))*2
            c.poly_line([(20+sd*8,21+i*3.5),(20+sd*13,23+i*3.5+ph*0.3),(20+sd*16,27+i*3.5+ph)],1.5,dk)
    c.ell(20,25,12.5,8.8,dk); c.ell(20,24,11.5,8,sh); c.ell(16,21,6,3.6,lt)
    c.poly_line([(13,28),(20,31),(27,28)],0.8,dk)
    op = 1.6+abs(swing(t))*2.6                                             # claw opening
    for sd in (-1,1):
        c.poly_line([(20+sd*10,20),(20+sd*13,13),(20+sd*11,9)],2.3,dk)
        c.poly_line([(20+sd*10,20),(20+sd*13,13),(20+sd*11,9)],1.2,cl)
        bx = 20+sd*11
        c.poly([(bx-2.2,9),(bx+2.2,9),(bx+op*sd*0.9+ sd*1.6,3),(bx+sd*0.2,4.6)],cl)
        c.poly([(bx-2.2,9),(bx+2.2,9),(bx-op*sd*0.9- sd*1.6+ sd*3,3),(bx+sd*0.2,5)],(226,98,52))
        c.ell(bx+sd*op*0.55+sd*1.6,3.6,0.9,0.9,tip)
    for sd in (-1,1):
        c.line((20+sd*3.5,15),(20+sd*3.5,12),0.8,dk); c.ell(20+sd*3.5,11.5,1.5,1.5,(255,255,255)); c.ell(20+sd*3.5,11.2,0.7,0.7,(15,10,10))
    return c, [dk,sh,lt,cl,tip,(226,98,52),(255,255,255),(15,10,10)], (50,16,14)

# ---------------------------------------------------------------- MOLE
def mole(t):
    c = Canvas(); fur=(126,92,66); dk=(78,54,40); lt=(168,128,96); pink=(244,160,176); claw=(240,230,205)
    c.poly_line([(20,33),(22,37),(25,38)],1.4,(226,150,160))               # tail
    c.ell(20,24,9.4,12.5,dk); c.ell(20,23.4,8.4,11.5,fur); c.ell(17,19,3.6,6.5,lt)
    c.ell(20,13,6.2,5.8,fur); c.ell(18,11.4,2.6,2,lt)
    for sd in (-1,1):
        ph = swing(t, 0 if sd<0 else 0.5)*2.6                              # digging stroke
        hx, hy = 20+sd*13, 15-ph
        c.line((20+sd*7,17),(hx,hy),3.0,dk); c.line((20+sd*7,17),(hx,hy),1.8,fur)
        c.ell(hx,hy-1,4.2,3.6,claw); c.ell(hx,hy-1,3.1,2.6,(255,248,230))
        for k in (-1.6,0,1.6): c.line((hx+k,hy-3),(hx+k*1.15,hy-6),0.9,(206,196,170))
    c.poly([(20,6.5),(23,8.6),(22.4,12),(17.6,12),(17,8.6)],pink)         # snout
    for k in range(6):
        a = k*math.pi/3 + t*0.35; c.line((20,4.6),(20+math.cos(a)*2.6,4.6+math.sin(a)*2.6),0.9,pink)  # star nose
    c.ell(20,4.6,1.6,1.6,(255,200,212)); c.ell(17.4,10.6,0.9,0.9,(15,10,10)); c.ell(22.6,10.6,0.9,0.9,(15,10,10))
    return c, [dk,fur,lt,pink,claw,(255,248,230),(206,196,170),(255,200,212),(226,150,160),(15,10,10)], (34,22,16)

# ---------------------------------------------------------------- BAT (flier)
def bat(t):
    c = Canvas(); mem=(120,76,168); memd=(78,48,122); memb=(168,120,214); body=(52,40,92); bodyl=(84,68,140)
    tipy = [6, 13, 22, 13][t]; mid = [10, 17, 24, 17][t]
    for sd in (-1,1):
        P = lambda x,y: (20+sd*x, y)
        c.poly([P(3.5,17),P(8,mid-2),P(19,tipy),P(15.5,tipy+8),P(12,tipy+5),P(9.5,mid+9),P(6.5,mid+7),P(3.5,27)],mem)
        c.poly([P(3.5,19),P(8,mid),P(15,tipy+3),P(9,mid+7),P(5,mid+6)],memb)
        for ex,ey in ((19,tipy),(15.5,tipy+8),(9.5,mid+9)): c.line(P(3.8,19),P(ex,ey),0.8,memd)
        c.poly([P(1.5,10.5),P(4.4,12),P(4.4,15),P(1.8,14.5)],body)         # ears
    c.ell(20,22.5,4.6,8,body); c.ell(18.6,20,1.8,4,bodyl)
    c.ell(20,13.6,4.2,3.8,body); c.ell(19,12.2,1.6,1.2,bodyl)
    c.ell(18.2,13,0.9,0.9,(255,70,70)); c.ell(21.8,13,0.9,0.9,(255,70,70))
    c.poly([(19,16),(20,18),(21,16)],(235,235,240))                       # fang
    c.poly([(19,30),(21,30),(20,35)],body)
    return c, [mem,memd,memb,body,bodyl,(255,70,70),(235,235,240)], (20,14,34)

SPECIES = {"slime":("ground",slime), "beetle":("ground",beetle), "spider":("ground",spider),
           "crab":("ground",crab), "mole":("ground",mole), "bat":("flier",bat)}

def death_frames(f0):
    outs = []
    for i,(sc,flash,al) in enumerate([(1.0,0.65,1.0),(0.9,0.35,0.9),(0.65,0.0,0.6),(0.35,0.0,0.3)]):
        f = f0.copy()
        if flash:
            px = f.load()
            for y in range(N):
                for x in range(N):
                    r,g,b,a = px[x,y]
                    if a: px[x,y] = (int(r+(255-r)*flash), int(g+(255-g)*flash), int(b+(255-b)*flash), 255)
        s = max(2,int(N*sc)); f = f.resize((s,s), Image.NEAREST)
        px = f.load()
        for y in range(s):
            for x in range(s):                                          # ordered-dither fade, keeps binary alpha
                if px[x,y][3] and ((x*3+y*5+i) % 10) / 10.0 >= al: px[x,y] = (0,0,0,0)
        cell = Image.new("RGBA",(N,N),(0,0,0,0)); cell.alpha_composite(f,((N-s)//2,(N-s)//2)); outs.append(cell)
    return outs

def fit_factor(cvs, margin=18.0):
    """One uniform scale for all frames so the largest extent stays inside the cell (+1px outline)."""
    ext = 0.0
    for cv in cvs:
        bb = cv.im.getchannel("A").point(lambda v: 255 if v > 0 else 0).getbbox()
        if bb:
            ext = max(ext, abs(bb[0]/K-20), abs(bb[2]/K-20), abs(bb[1]/K-20), abs(bb[3]/K-20))
    return min(1.0, margin/ext) if ext else 1.0

def rescale(cv, f):
    if f >= 0.999: return cv
    sz = max(1, int(N*K*f)); small = cv.im.resize((sz, sz), Image.LANCZOS)
    out = Image.new("RGBA", cv.im.size, (0,0,0,0)); o = (N*K-sz)//2
    out.alpha_composite(small, (o, o)); cv.im = out; return cv

def build(name):
    kind, fn = SPECIES[name]; walk = []
    parts = [fn(t) for t in range(4)]; f = fit_factor([p[0] for p in parts])
    for cv, pal, ol in parts: walk.append(finalize(rescale(cv, f), pal, ol))
    sheet = Image.new("RGBA",(160,120),(0,0,0,0))
    for i,f in enumerate(walk): sheet.alpha_composite(f,(i*40,0))
    for i,f in enumerate(death_frames(walk[0])): sheet.alpha_composite(f,(i*40,40))
    d = os.path.join(OUT, name); os.makedirs(d, exist_ok=True)
    sheet.save(os.path.join(d, f"{name}_{kind}_sheet.png"))
    if ORIG:
        src = os.path.join(ORIG, name, f"{name}_{kind}_frames.json")
        if os.path.exists(src): shutil.copy(src, os.path.join(d, f"{name}_{kind}_frames.json"))
    return sheet

if __name__ == "__main__":
    for n in SPECIES: build(n)
    print("built", ", ".join(SPECIES))

# ---------------------------------------------------------------- SLIME v2 (robo-eye, from user's reference)
def slime_robo(t):
    c = Canvas()
    P = [(11.5,9.5,24.0),(12.8,8.2,25.2),(9.6,12.6,21.8),(11.2,10.2,23.6)][t]      # rx, ry, cy per frame
    rx, ry, cy = P
    pud=(150,236,46); pudr=(92,192,34); deep=(38,118,30); shade=(70,170,28); base=(124,222,30)
    lt=(176,250,56); hi=(236,255,212)
    # puddle: scalloped lobes around/below the body (trail grows behind = lower side when lunging)
    lobes=[(-11,3,5,3),(-6,7.5,6,3),(2,8.5,6.5,3.2),(10,5.5,5.5,3),(12.5,0.5,3.6,2.4),(-13,-1,3.2,2.2)]
    for dx,dy,lx,ly in lobes:
        c.ell(20+dx,cy+dy,lx,ly,pudr); 
    for dx,dy,lx,ly in lobes:
        c.ell(20+dx,cy+dy-0.5,lx-0.9,ly-0.8,pud)
    c.ell(20,cy+2,rx+3.2,ry*0.62+2,pudr); c.ell(20,cy+1.6,rx+2.3,ry*0.62+1.2,pud)
    # body dome
    c.ell(20,cy,rx+0.8,ry+0.8,deep); c.ell(20,cy-0.3,rx,ry,shade); c.ell(19.3,cy-1,rx-1.6,ry-1.8,base)
    c.ell(17,cy-ry*0.35,rx*0.55,ry*0.38,lt); c.ell(15.2,cy-ry*0.5,2.6,1.5,hi)           # gloss
    c.ell(24.5,cy+ry*0.45,rx*0.4,ry*0.22,(150,238,50))                                   # glassy lower sheen
    # camera-eye housing (front of body = top of sprite)
    ex, ey = 21.0, cy-ry*0.45
    c.ell(ex-6.0,ey+0.8,1.8,2.7,(120,126,138)); c.ell(ex-6.0,ey+0.5,1.1,1.9,(190,194,204))   # side clamp
    c.ell(ex,ey,6.6,6.4,(30,30,38)); c.ell(ex,ey,6.0,5.8,(176,181,192)); c.ell(ex-0.9,ey-1.0,5.0,4.7,(214,218,226))  # metal ring
    c.ell(ex,ey,4.5,4.4,(44,46,56)); c.ell(ex,ey,3.5,3.4,(26,26,34))                        # dark housing
    c.ell(ex,ey,3.0,2.9,(222,38,34)); c.ell(ex-0.5,ey-0.5,1.8,1.7,(255,150,46)); c.ell(ex-1.0,ey-1.1,0.8,0.8,(255,236,204))
    # droplets
    drops=[[(6,10,1.7),(31,12,1.4),(34,24,1.2),(8,30,1.3)],
           [(5,14,1.5),(33,11,2.0),(35,20,1.1),(6,27,1.5)],
           [(10,34,1.6),(14,37,1.2),(24,36,1.5),(29,33,1.2),(6,31,1.0)],
           [(7,12,1.4),(32,10,1.7),(35,26,1.1),(9,32,1.2)]][t]
    for dx,dy,r in drops:
        c.ell(dx,dy,r+0.5,r+0.5,deep); c.ell(dx,dy,r,r,base); c.ell(dx-r*0.3,dy-r*0.35,r*0.38,r*0.38,hi)
    pal=[deep,shade,base,lt,hi,pud,pudr,(30,30,38),(120,126,138),(190,194,204),(176,181,192),(214,218,226),
         (44,46,56),(26,26,34),(222,38,34),(255,150,46),(255,236,204),(150,238,50)]
    return c, pal, (12,46,14)

SPECIES["slime"] = ("ground", slime_robo)
