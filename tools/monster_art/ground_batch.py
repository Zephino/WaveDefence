#!/usr/bin/env python3
"""Ground monster batch (top-down, facing UP). Reuses Canvas/finalize/build from gen_monsters.py."""
import math, sys, os
sys.argv = [sys.argv[0]] + sys.argv[1:]
import gen_monsters as g
from gen_monsters import Canvas, swing

def legs(c, rows, col, t, w=1.4, phase_step=0.5):
    """rows: [(y0, x_off, out, down)] mirrored left/right, alternating tripod gait."""
    for i,(y0,xo,out,dn) in enumerate(rows):
        for sd in (-1,1):
            ph = swing(t, phase_step*((i+(0 if sd<0 else 1))%2))*1.8
            c.poly_line([(20+sd*xo,y0),(20+sd*(xo+out*0.6),y0+dn*0.4+ph*0.5),(20+sd*(xo+out),y0+dn+ph)],w,col)

# ---------------- CRAWLER (centipede, teal + yellow bands; also the SNAKE species)
def crawler(t):
    c=Canvas(); dk=(14,84,90); md=(30,160,150); lt=(110,226,200); st=(250,206,64); lg=(18,56,60); mand=(255,150,50)
    segs=[(13.5,5.8),(19,6.2),(24.5,6.0),(30,5.4),(35,4.2)]
    for i,(y,rx) in enumerate(segs):
        ox=math.sin(t*math.pi/2+i*0.9)*1.0
        for sd in (-1,1):
            ph=swing(t,0.25*i+(0.5 if sd>0 else 0))*1.6
            c.poly_line([(20+ox+sd*rx*0.8,y),(20+ox+sd*(rx+3),y-1+ph),(20+ox+sd*(rx+4.5),y+1.5+ph)],1.2,lg)
    for i,(y,rx) in enumerate(segs):
        ox=math.sin(t*math.pi/2+i*0.9)*1.0
        c.ell(20+ox,y,rx+0.6,3.4,dk); c.ell(20+ox,y-0.3,rx,2.9,md); c.ell(20+ox-1.4,y-1.2,rx*0.45,0.9,lt)
        c.line((20+ox-rx*0.7,y+0.9),(20+ox+rx*0.7,y+0.9),0.9,st)
    c.ell(20,8,5,4.2,dk); c.ell(20,7.6,4.2,3.4,md); c.ell(18.6,6.6,1.6,1.0,lt)
    for sd in (-1,1):
        c.poly_line([(20+sd*2.2,4.8),(20+sd*3.4,2.6),(20+sd*1.6,1.4)],1.1,mand)
        c.poly_line([(20+sd*3.4,6),(20+sd*7,2.8+swing(t)*0.8)],0.7,lg)
        c.ell(20+sd*2.2,7.4,0.9,0.9,(255,236,120))
    return c,[dk,md,lt,st,lg,mand,(255,236,120)],(8,40,44)

# ---------------- PILLBUG (slate-blue armoured isopod)
def pillbug(t):
    c=Canvas(); dk=(36,48,74); md=(78,100,142); lt=(146,170,208); hi=(204,220,244); lg=(26,30,44)
    legs(c,[(13+i*3.4,7.5,3.2,1.2) for i in range(6)],lg,t,1.0,0.35)
    c.ell(20,22,9.6,14.2,dk)
    for i in range(8):
        y=10.5+i*3.2; w=[6.4,7.8,8.8,9.2,9.2,8.8,7.8,6.2][i]
        c.ell(20,y+0.6,w,2.3,dk); c.ell(20,y,w-0.5,1.9,md); c.ell(20-w*0.25,y-0.8,w*0.45,0.6,lt)
    c.ell(16.5,14,2.4,1.0,hi)
    c.ell(20,7.4,5.2,2.8,dk); c.ell(20,7,4.4,2.2,md)
    for sd in (-1,1):
        c.poly_line([(20+sd*3,5.6),(20+sd*6,2.6+swing(t,0.25*sd)*0.8),(20+sd*8,2)],0.9,lg)
        c.poly([(20+sd*3,35.4),(20+sd*5.4,37.4),(20+sd*3.8,34.2)],md)
    return c,[dk,md,lt,hi,lg],(16,20,34)

# ---------------- TORTOISE (khaki hex shell, gold seams)
def tortoise(t):
    c=Canvas(); skin=(108,148,78); skind=(64,96,48); rim=(72,62,38); sh=(96,120,52); pl=(150,172,76); seam=(236,200,72); hi=(214,232,150)
    for (x,y,ph) in ((9,13,0),(31,13,0.5),(9,30,0.5),(31,30,0)):
        dy=swing(t,ph)*1.6; c.ell(x,y+dy,3.6,3.2,skind); c.ell(x,y+dy-0.4,2.8,2.4,skin)
    c.ell(20,6+swing(t)*0.4,3.6,4,skind); c.ell(20,5.6+swing(t)*0.4,2.9,3.2,skin)
    c.ell(18.6,4.6,0.7,0.7,(20,20,20)); c.ell(21.4,4.6,0.7,0.7,(20,20,20))
    c.poly([(20,36),(18.6,33),(21.4,33)],skind)
    c.ell(20,21.5,13,13.6,rim); c.ell(20,21,12,12.6,sh)
    hexes=[(20,21,4.6)]+[(20+math.cos(a)*8,21+math.sin(a)*8.3,3.6) for a in [i*math.pi/3+math.pi/6 for i in range(6)]]
    for hx,hy,r in hexes:
        pts=[(hx+math.cos(k*math.pi/3)*r,hy+math.sin(k*math.pi/3)*r) for k in range(6)]
        c.poly(pts,seam); c.poly([(hx+(x-hx)*0.8,hy+(y-hy)*0.8) for x,y in pts],pl)
    c.ell(15,14.5,3.4,1.8,hi)
    return c,[skin,skind,rim,sh,pl,seam,hi,(20,20,20)],(36,30,18)

# ---------------- URCHIN (hot-pink spikes, slowly turning)
def urchin(t):
    c=Canvas(); core=(176,40,128); cored=(104,16,80); sp=(240,110,196); tip=(255,214,240); ctr=(255,176,90)
    off=t*(2*math.pi/16)/4
    for k in range(16):
        a=off+k*2*math.pi/16; L=13.5 if k%2==0 else 10.5
        x1,y1=20+math.cos(a)*L,20+math.sin(a)*L
        c.line((20+math.cos(a)*5,20+math.sin(a)*5),(x1,y1),1.5,sp); c.ell(x1,y1,0.8,0.8,tip)
    c.ell(20,20,8,8,cored); c.ell(20,20,7,7,core); c.ell(17.8,17.6,2.8,2.0,sp)
    for k in range(5):
        a=-math.pi/2+k*2*math.pi/5; c.line((20,20),(20+math.cos(a)*3.4,20+math.sin(a)*3.4),0.9,ctr)
    c.ell(20,20,1.3,1.3,(255,236,200))
    return c,[core,cored,sp,tip,ctr,(255,236,200)],(60,6,44)

# ---------------- SCARAB (gold + turquoise inlay)
def scarab(t):
    c=Canvas(); gd=(232,182,48); gdd=(150,100,26); gl=(255,232,140); tq=(36,186,186); tqd=(16,100,110); lg=(34,30,40)
    legs(c,[(14,6,5,-3),(20,8,5,0),(26,8,5,4)],lg,t,1.4)
    c.ell(20,25,9.4,10.6,gdd); c.ell(20,24.4,8.6,9.8,gd)
    c.line((20,15),(20,34.4),1.0,tqd); c.line((20,15.5),(20,33.8),0.5,tq)
    for sd in (-1,1): c.ell(20+sd*4.4,26,1.6,2.6,tqd); c.ell(20+sd*4.4,25.6,1.0,1.9,tq)
    c.ell(16.2,20,2.6,3.6,gl)
    c.ell(20,13.2,7.2,4.6,gdd); c.ell(20,12.8,6.4,3.9,gd); c.line((14.6,13.6),(25.4,13.6),1.0,tq)
    for k in range(5):                                         # toothed scoop head
        x=15.4+k*2.3; c.poly([(x,8.6),(x+2.3,8.6),(x+1.15,4.4)],gd)
    c.ell(20,8.8,5.2,1.8,gdd); c.ell(17.6,9.6,0.8,0.8,(255,70,60)); c.ell(22.4,9.6,0.8,0.8,(255,70,60))
    return c,[gd,gdd,gl,tq,tqd,lg,(255,70,60)],(40,26,10)

# ---------------- TICK (orange shield, swollen slate abdomen)
def tick(t):
    c=Canvas(); ab=(112,122,144); abd=(62,68,88); abl=(176,186,206); sc=(206,104,42); scd=(130,60,24); lg=(58,36,30)
    legs(c,[(13,5,6,-4),(15,6,7,-1),(17,6,7,2),(19,5,6,5)],lg,t,1.3)
    c.ell(20,25,10.4,11.2,abd); c.ell(20,24.6,9.6,10.4,ab); c.ell(16.6,20.5,3.8,4.6,abl); c.ell(15.6,19.4,1.4,1.6,(232,236,246))
    for k in range(3): c.line((20+(k-1)*3.6,28),(20+(k-1)*3.0,33),0.7,abd)
    c.ell(20,15,6.4,5.2,scd); c.ell(20,14.6,5.6,4.4,sc); c.ell(18.4,13.4,2.0,1.4,(240,150,80))
    c.ell(20,8.6,2.8,3.0,scd); c.ell(20,8.4,2.1,2.3,sc)
    c.poly_line([(19,7),(18.4,4.2)],0.9,scd); c.poly_line([(21,7),(21.6,4.2)],0.9,scd); c.line((20,7),(20,4.6),0.8,(255,200,120))
    return c,[ab,abd,abl,sc,scd,lg,(232,236,246),(240,150,80),(255,200,120)],(28,22,26)

# ---------------- SLUG (banana yellow, eye stalks, slime trail)
def slug(t):
    c=Canvas(); y=(244,204,44); yd=(188,138,20); yl=(255,238,130); sp=(140,92,26); tr=(214,236,150)
    st=[0,0.6,0,-0.6][t]; L=[14,14.8,14,13.4][t]
    c.ell(20,35.5,4.6,2.4,tr); c.ell(20,37,3.2,1.4,tr)
    c.ell(20,22,7.6,L,yd); c.ell(20,21.6,6.8,L-0.8,y); c.ell(17.4,24,2.2,L*0.55,yl)
    for (x,yy) in ((22.6,20),(18,28),(23,30),(21,14.5)): c.ell(x,yy,1.1,1.1,sp)
    c.ell(20,13.4,6.2,4.8,yd); c.ell(20,13,5.4,4.0,(250,214,70)); c.ell(20,13,2.2,1.6,yd)
    for sd in (-1,1):
        tx=20+sd*(4.4+st*sd*0.6); c.line((20+sd*2,9.4),(tx,3.4),1.2,yd); c.ell(tx,3,1.6,1.6,(40,30,20)); c.ell(tx-0.4,2.6,0.5,0.5,(255,255,255))
    return c,[y,yd,yl,sp,tr,(250,214,70),(40,30,20),(255,255,255)],(80,56,8)

# ---------------- JELLY (ground jelly: glossy cyan bell, glowing core, trailing tentacles)
def jelly(t):
    c=Canvas(); bd=(36,104,196); bm=(84,170,238); bl=(170,226,255); hi=(240,252,255); core=(255,120,196); ten=(120,200,250); tend=(52,128,212)
    for k in range(5):
        x0=12+k*4; pts=[]
        for i in range(6):
            yy=22+i*2.8; pts.append((x0+math.sin(t*math.pi/2+i*0.9+k)*1.4,yy))
        c.poly_line(pts,1.5,tend); c.poly_line(pts[:4],0.7,ten)
    c.ell(20,15.5,11,9.4,bd); c.ell(20,15,10.2,8.6,bm); c.ell(20,16,7,5.6,(110,190,246))
    for k in range(4):
        a=k*math.pi/2+t*0.2; c.ell(20+math.cos(a)*3.4,16+math.sin(a)*2.8,1.4,1.4,core)
    c.ell(20,16,1.6,1.6,(255,200,230)); c.ell(15.6,10.6,3.6,2.0,bl); c.ell(14.6,10,1.4,0.9,hi)
    c.line((10,21.6),(30,21.6),1.2,bd)
    return c,[bd,bm,bl,hi,core,ten,tend,(110,190,246),(255,200,230)],(14,40,96)

# ---------------- ARMADILLO (the WRECKER: steel bands, red optics, ram claws)
def armadillo(t):
    c=Canvas(); dk=(34,36,50); md=(100,108,134); lt=(166,176,200); hi=(214,220,234); red=(250,60,48); redh=(255,170,150); lg=(30,30,40)
    for (x,y,ph) in ((9.5,14,0),(30.5,14,0.5),(9.5,30,0.5),(30.5,30,0)):
        dy=swing(t,ph)*1.6; c.ell(x,y+dy,3.0,2.6,lg)
    c.poly([(19,35),(21,35),(20,39)],md)
    c.ell(20,23,11.6,13.6,dk)
    for i in range(6):
        yy=14+i*3.6; w=[9.4,10.8,11.2,11.2,10.6,9.0][i]
        c.ell(20,yy+0.8,w,2.4,dk); c.ell(20,yy,w-0.6,2.0,md); c.ell(20-w*0.3,yy-0.8,w*0.4,0.6,lt)
        c.line((20-w+1.8,yy+1.5),(20+w-1.8,yy+1.5),0.7,red if (i+t)%2==0 else (150,30,30))
    c.ell(15.6,15,2.6,1.0,hi)
    c.ell(20,8.6,6,4.6,dk); c.ell(20,8.2,5.2,3.8,md); c.ell(18,7.2,1.8,1.0,lt)
    c.line((16.6,7.6),(23.4,7.6),1.6,(80,10,10)); c.line((17.2,7.6),(22.8,7.6),1.0,red); c.ell(20,7.6,0.9,0.7,redh)
    for sd in (-1,1):                                          # ram claws
        c.poly([(20+sd*3.4,5.6),(20+sd*6.2,1.6),(20+sd*5.4,5.8)],hi); c.poly([(20+sd*3.4,5.6),(20+sd*6.2,1.6),(20+sd*4.6,4.4)],lt)
    return c,[dk,md,lt,hi,red,redh,lg,(80,10,10)],(14,14,22)

# ---------------- ROLLER (white rolling robo-ball, orange band rolls, cyan visor)
def roller(t):
    c=Canvas(); wh=(120,196,200); sh=(62,140,150); dk=(28,70,82); org=(252,204,40); orgd=(40,40,44); cy=(255,72,60); cyd=(120,20,20)
    c.ell(20,20.6,13,13,dk); c.ell(20,20,12.4,12.4,sh); c.ell(19,19,11.2,11.2,wh)
    for dy in ([-8,-2.5,3,8.5][t], [-8,-2.5,3,8.5][(t+2)%4]):
        yy=20+dy; w=math.sqrt(max(0,12.2**2-dy**2))
        c.ell(20,yy,w,1.7,orgd); c.ell(20,yy-0.3,w-0.6,1.1,org)
        for k in range(-3,4): c.line((20+k*3.2-0.6,yy-1),(20+k*3.2+0.6,yy+0.8),0.8,orgd)
    c.ell(20,8.6,5.6,2.4,cyd); c.ell(20,8.4,4.6,1.6,cy); c.ell(18.4,8.0,1.2,0.6,(255,200,190))
    c.ell(14.6,13.6,3.2,2.2,(200,240,240))
    return c,[wh,sh,dk,org,orgd,cy,cyd,(255,200,190),(200,240,240)],(10,30,36)

NEW = {"crawler":crawler,"pillbug":pillbug,"tortoise":tortoise,"urchin":urchin,"scarab":scarab,
       "tick":tick,"slug":slug,"jelly":jelly,"armadillo":armadillo,"roller":roller}
for k,fn in NEW.items(): g.SPECIES[k]=("ground",fn)
g.SPECIES["slime"]=("ground",g.slime_robo)
GROUND=["slime","beetle","spider","crab","crawler","pillbug","tortoise","urchin","mole","scarab","tick","slug","jelly","armadillo","roller"]
if __name__=="__main__":
    out=sys.argv[1] if len(sys.argv)>1 else "out"; g.OUT=out; g.ORIG="/home/claude/WaveDefence/assets/sprites"
    for n in GROUND: g.build(n)
    print("built",len(GROUND))
