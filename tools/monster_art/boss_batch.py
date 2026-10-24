#!/usr/bin/env python3
"""Boss batch: 80x80 frames, 320x240 sheets (row0 walk 4, row1 death 4, row2 attack 0). Top-down, facing UP."""
import math, os, shutil
from PIL import Image, ImageDraw
K=6; N=80
class C:
    def __init__(s): s.im=Image.new("RGBA",(N*K,N*K),(0,0,0,0)); s.d=ImageDraw.Draw(s.im); s.pal=set()
    def _c(s,c): s.pal.add(tuple(c)); return c
    def P(s,pts): return [(x*K,y*K) for x,y in pts]
    def ell(s,cx,cy,rx,ry,c):
        if rx>0 and ry>0: s.d.ellipse([(cx-rx)*K,(cy-ry)*K,(cx+rx)*K,(cy+ry)*K],fill=s._c(c))
    def poly(s,pts,c): s.d.polygon(s.P(pts),fill=s._c(c))
    def line(s,a,b,w,c): s.d.line(s.P([a,b]),fill=s._c(c),width=max(1,int(w*K)))
    def pl(s,pts,w,c): s.d.line(s.P(pts),fill=s._c(c),width=max(1,int(w*K)),joint="curve")
    def rect(s,x0,y0,x1,y1,c): s.d.rectangle([x0*K,y0*K,x1*K,y1*K],fill=s._c(c))
def fit(cs, margin=37.0):
    ext=0
    for c in cs:
        bb=c.im.getchannel("A").getbbox()
        if bb: ext=max(ext,abs(bb[0]/K-40),abs(bb[2]/K-40),abs(bb[1]/K-40),abs(bb[3]/K-40))
    f=min(1.0,margin/ext) if ext else 1.0
    if f<0.999:
        for c in cs:
            sz=int(N*K*f); sm=c.im.resize((sz,sz),Image.LANCZOS); o=Image.new("RGBA",c.im.size,(0,0,0,0)); o.alpha_composite(sm,((N*K-sz)//2,)*2); c.im=o
    return cs
def finalize(c, outline):
    sm=c.im.resize((N,N),Image.BOX); px=sm.load(); pal=list(c.pal); out=Image.new("RGBA",(N,N),(0,0,0,0)); op=out.load()
    for y in range(N):
        for x in range(N):
            r,g,b,a=px[x,y]
            if a<110: continue
            op[x,y]=(*min(pal,key=lambda p:(p[0]-r)**2+(p[1]-g)**2+(p[2]-b)**2),255)
    res=out.copy(); rp=res.load()
    for y in range(N):
        for x in range(N):
            if op[x,y][3]==0:
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    xx,yy=x+dx,y+dy
                    if 0<=xx<N and 0<=yy<N and op[xx,yy][3]: rp[x,y]=(*outline,255); break
    return res
def death(f0):
    outs=[]
    for i,(sc,fl,al) in enumerate([(1.0,0.6,1.0),(0.9,0.3,0.85),(0.65,0,0.55),(0.35,0,0.3)]):
        f=f0.copy(); px=f.load()
        if fl:
            for y in range(N):
                for x in range(N):
                    r,g,b,a=px[x,y]
                    if a: px[x,y]=(int(r+(255-r)*fl),int(g+(255-g)*fl),int(b+(255-b)*fl),255)
        s=max(2,int(N*sc)); f=f.resize((s,s),Image.NEAREST); px=f.load()
        for y in range(s):
            for x in range(s):
                if px[x,y][3] and ((x*3+y*5+i)%10)/10.0>=al: px[x,y]=(0,0,0,0)
        cell=Image.new("RGBA",(N,N),(0,0,0,0)); cell.alpha_composite(f,((N-s)//2,)*2); outs.append(cell)
    return outs
def sw(t,ph=0): return math.sin((t/4+ph)*2*math.pi)

# ---------------- COLOSSUS: rock golem with lava cracks and huge fists
def colossus(t):
    c=C(); r0=(58,52,50); r1=(104,94,86); r2=(150,138,124); r3=(196,184,166); lava=(255,120,30); lavh=(255,220,90); eye=(255,200,60)
    for sd in (-1,1):                                          # fists swing alternately
        fy=20+sw(t,0 if sd<0 else 0.5)*5
        c.pl([(40+sd*16,40),(40+sd*24,30),(40+sd*24,fy+6)],7,r0); c.pl([(40+sd*16,40),(40+sd*24,30),(40+sd*24,fy+6)],5,r1)
        c.ell(40+sd*24,fy,10,9,r0); c.ell(40+sd*24,fy-0.6,9,8,r1); c.ell(40+sd*22,fy-3,5,3.6,r2)
        c.line((40+sd*20,fy+1),(40+sd*28,fy-2),1.4,lava); c.line((40+sd*21,fy+4),(40+sd*27,fy+3),1.0,lava)
    c.ell(40,50,24,22,r0); c.ell(40,49,22.6,20.6,r1)
    for (x,y,rx,ry) in ((30,40,9,7),(50,40,9,7),(40,56,12,9),(27,57,6,6),(53,57,6,6)): c.ell(x,y,rx,ry,r2); c.ell(x-2,y-2,rx*0.5,ry*0.45,r3)
    for pts in ([(28,46),(36,50),(34,58),(40,64)],[(52,44),(46,52),(50,60)],[(40,36),(42,44),(38,50)]):
        c.pl(pts,2.6,lava); c.pl(pts,1.0,lavh)
    c.ell(40,26,11,9,r0); c.ell(40,25.4,10,8,r1); c.ell(37,22,4.6,3.2,r2)
    c.rect(32,24.6,48,27.6,(40,20,10)); c.ell(35.5,26,2.4,1.6,eye); c.ell(44.5,26,2.4,1.6,eye); c.ell(35,25.6,0.8,0.6,(255,255,220))
    return c,(20,14,12)

# ---------------- IRON MAW: steel beast led by a spinning toothed grinder mouth
def iron_maw(t):
    c=C(); m0=(36,38,50); m1=(84,90,108); m2=(140,148,168); m3=(198,206,222); red=(240,50,40); redh=(255,150,110); tooth=(236,232,214); rv=(255,190,60)
    for (x,y,ph) in ((20,46,0),(60,46,0.5),(22,66,0.5),(58,66,0)):
        dy=sw(t,ph)*3; c.ell(x,y+dy,6,5,m0); c.ell(x,y+dy-0.5,5,4,m1)
    c.ell(40,56,20,18,m0); c.ell(40,55,18.8,16.8,m1)
    for i in range(4): c.ell(40,46+i*6,17-i*1.6,2.4,m2); c.ell(36,45+i*6,8-i,0.9,m3)
    for (x,y) in ((26,52),(54,52),(30,64),(50,64)): c.ell(x,y,1.2,1.2,rv)
    c.ell(40,28,22,21,m0); c.ell(40,27.6,20.6,19.6,m2); c.ell(40,27.6,17,16,m1)
    c.ell(40,27.6,14,13,(60,10,10)); c.ell(40,27.6,8,7.4,red); c.ell(40,27.6,4,3.6,redh)
    rot=t*(2*math.pi/14)/4
    for k in range(14):                                         # teeth pointing inward, rotating
        a=rot+k*2*math.pi/14; bx,by=40+math.cos(a)*15.6,27.6+math.sin(a)*14.6
        tx,ty=40+math.cos(a)*8.6,27.6+math.sin(a)*8.0; px,py=-math.sin(a)*2.2,math.cos(a)*2.2
        c.poly([(bx+px,by+py),(tx,ty),(bx-px,by-py)],tooth)
    for sd in (-1,1): c.ell(40+sd*13,10,3,2.4,(60,10,10)); c.ell(40+sd*13,9.8,2.2,1.6,red); c.ell(40+sd*12.4,9.4,0.7,0.6,redh)
    return c,(14,14,20)

# ---------------- JUGGERNAUT: armoured tank-beast with scrolling treads and a front plow
def juggernaut(t):
    c=C(); tr=(30,30,36); trl=(80,80,90); h0=(60,66,40); h1=(118,128,64); h2=(170,180,94); h3=(214,222,140); hz=(250,200,40); hzd=(30,30,30); can=(70,74,88)
    for sd in (-1,1):
        x0=40+sd*22; c.rect(x0-7,10,x0+7,72,tr)
        for i in range(10):
            y=10+((i*7+t*1.75)%62); c.rect(x0-6.4,y,x0+6.4,y+2.2,trl)
        for y in (16,30,44,58,68): c.ell(x0,y,3,3,(52,52,60))
    c.rect(24,18,56,68,h0); c.rect(25.4,19,54.6,66.6,h1); c.rect(27,20,40,40,h2); c.rect(28,21,34,26,h3)
    for i in range(6):                                          # hazard stripes on the rear
        x=26+i*5; c.poly([(x,60),(x+3,60),(x+1,66),(x-2,66)],hz if i%2==0 else hzd)
    c.poly([(20,16),(60,16),(56,8),(24,8)],h0); c.poly([(22,15),(58,15),(55,9.4),(25,9.4)],h2)  # plow
    for i in range(5): c.line((27+i*6.5,9.6),(27+i*6.5,14.6),1.0,h0)
    c.ell(40,42,11,11,h0); c.ell(40,41.4,9.6,9.6,h1); c.ell(37,38,4.6,3.6,h2)
    c.rect(37.6,18,42.4,34,can); c.rect(38.6,18,41.4,33,(120,124,140)); c.rect(36.6,16,43.4,19,can)
    c.ell(40,42,2.6,2.6,(255,70,50)); c.ell(39.4,41.4,0.9,0.9,(255,200,180))
    return c,(16,18,10)

# ---------------- LEVIATHAN: deep-sea kraken with glowing spots and waving tentacles
def leviathan(t):
    c=C(); d0=(14,40,70); d1=(24,86,120); d2=(40,140,170); d3=(110,210,220); glow=(120,255,240); eye=(255,226,80); fin=(30,110,150)
    for k in range(8):
        x0=22+k*5.2; pts=[]
        for i in range(9):
            yy=46+i*3.6; pts.append((x0+(x0-40)*i*0.06+math.sin(t*math.pi/2+i*0.7+k*0.9)*2.6,yy))
        c.pl(pts,4.2-0.2*abs(k-3.5),d0); c.pl(pts,2.6-0.15*abs(k-3.5),d1)
        for i in (2,4,6): c.ell(pts[i][0],pts[i][1],0.9,0.9,d3)
    for sd in (-1,1):
        f=sw(t)*2; c.poly([(40+sd*14,22),(40+sd*(30+f),14),(40+sd*(28+f),30),(40+sd*15,34)],fin)
    c.ell(40,30,17,22,d0); c.ell(40,29.4,15.6,20.6,d1); c.ell(36,22,8,10,d2); c.ell(34,18,3.6,4,d3)
    for (x,y,r) in ((32,32,1.6),(48,30,1.8),(44,40,1.4),(36,42,1.2),(40,22,1.2),(50,20,1.0)):
        on=(int(x+y)+t)%3!=0; c.ell(x,y,r+0.6,r+0.6,d2); c.ell(x,y,r,r,glow if on else d3)
    for sd in (-1,1): c.ell(40+sd*8,12,4,3.2,(20,20,30)); c.ell(40+sd*8,11.6,3.0,2.4,eye); c.ell(40+sd*8,11.6,1.2,1.8,(20,20,30)); c.ell(40+sd*7.2,10.8,0.8,0.6,(255,255,230))
    return c,(6,18,34)

# ---------------- OVERSEER: giant floating eye in a spiked rotating ring, trailing cables
def overseer(t):
    c=C(); v0=(44,20,70); v1=(96,46,150); v2=(150,90,210); m0=(40,40,56); m1=(110,112,134); m2=(180,182,204); white=(240,236,246); iris=(240,50,60); irh=(255,150,120); pup=(20,10,20)
    for k in range(5):
        x0=28+k*6; pts=[]
        for i in range(8):
            pts.append((x0+math.sin(t*math.pi/2+i*0.8+k)*2.2,52+i*3.4))
        c.pl(pts,2.6,m0); c.pl(pts,1.2,v2); c.ell(pts[-1][0],pts[-1][1],1.6,1.6,(255,120,220))
    rot=t*(2*math.pi/6)/4
    c.ell(40,38,27,27,v0); c.ell(40,38,25.6,25.6,v1)
    for k in range(6):
        a=rot+k*math.pi/3; bx,by=40+math.cos(a)*25,38+math.sin(a)*25; tx,ty=40+math.cos(a)*35,38+math.sin(a)*35
        px,py=-math.sin(a)*3.2,math.cos(a)*3.2
        c.poly([(bx+px,by+py),(tx,ty),(bx-px,by-py)],m1); c.poly([(bx+px*0.4,by+py*0.4),(tx,ty),(bx,by)],m2)
    c.ell(40,38,22,22,m0); c.ell(40,38,20.6,20.6,m1)
    for k in range(12):
        a=k*math.pi/6+rot; c.ell(40+math.cos(a)*21.3,38+math.sin(a)*21.3,1.0,1.0,(255,120,220) if k%2==0 else m2)
    c.ell(40,38,17.6,17.6,(200,190,214)); c.ell(39,37,16.6,16.6,white)
    look=[0,0.6,0,-0.6][t]
    c.ell(40+look,30,10,9,iris); c.ell(40+look,29.6,7.6,6.8,irh); c.ell(40+look,30,6,5.4,iris)
    c.ell(40+look,30,3.6,4.6,pup); c.ell(37+look,27,1.8,1.4,(255,255,255))
    c.ell(31,41,4,2.2,(255,255,255))
    return c,(16,8,24)

BOSSES={"colossus_v2":colossus,"iron_maw_v2":iron_maw,"juggernaut_v2":juggernaut,"leviathan_v2":leviathan,"overseer_v2":overseer}
def build(sid, out, orig):
    fn=BOSSES[sid]; parts=[fn(t) for t in range(4)]; cs=fit([p[0] for p in parts])
    walk=[finalize(cs[i],parts[i][1]) for i in range(4)]
    sh=Image.new("RGBA",(320,240),(0,0,0,0))
    for i,f in enumerate(walk): sh.alpha_composite(f,(i*80,0))
    for i,f in enumerate(death(walk[0])): sh.alpha_composite(f,(i*80,80))
    d=os.path.join(out,sid); os.makedirs(d,exist_ok=True); sh.save(os.path.join(d,f"{sid}_boss_sheet.png"),optimize=True)
    src=os.path.join(orig,sid,f"{sid}_boss_frames.json")
    if os.path.exists(src): shutil.copy(src,os.path.join(d,f"{sid}_boss_frames.json"))
if __name__=="__main__":
    import sys
    for s in BOSSES: build(s, sys.argv[1], sys.argv[2])
    print("built",len(BOSSES))
