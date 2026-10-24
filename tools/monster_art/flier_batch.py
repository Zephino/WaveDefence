#!/usr/bin/env python3
"""Flier batch (top-down, facing UP, 40px). Reuses gen_monsters Canvas/finalize/build."""
import math, sys
import gen_monsters as g
from gen_monsters import Canvas, swing

def wings4(c, t, root_y, span, fwd, back, col, colhi, vein, flap=(1.0,0.75,0.45,0.75)):
    """Insect wings (2 pairs) as long ellipse-ish polygons; flap scales the span per frame."""
    k=flap[t]
    for sd in (-1,1):
        for (ry,ang,ln,wd) in ((root_y,-0.35,span*fwd,3.4),(root_y+3,0.35,span*back,2.8)):
            a=ang if sd>0 else math.pi-ang; L=ln*k
            tx,ty=20+math.cos(a)*L*(1 if sd>0 else 1),ry+math.sin(a)*L*0.6
            tx=20+sd*abs(math.cos(ang))*L; ty=ry+math.sin(ang)*L*0.55
            px,py=0,wd
            c.poly([(20+sd*2,ry-1.2),(20+sd*(2+L*0.5),ry-wd*0.9+math.sin(ang)*L*0.25),(tx,ty),(20+sd*(2+L*0.5),ry+wd*0.9+math.sin(ang)*L*0.3),(20+sd*2,ry+1.2)],col)
            c.line((20+sd*2.5,ry),(tx-sd*1.5,ty),0.6,vein); c.ell(20+sd*(2+L*0.35),ry-wd*0.3+math.sin(ang)*L*0.2,L*0.18,wd*0.35,colhi)

# ---------------- WASP (yellow/black, glassy wings)
def wasp(t):
    c=Canvas(); y=(250,206,40); yd=(196,140,20); bk=(30,28,36); w=(200,230,250); wh=(240,250,255); wv=(130,170,200); eye=(220,40,40)
    wings4(c,t,15,14,1.0,0.8,w,wh,wv)
    c.ell(20,26,5.2,8.4,bk); c.ell(20,25.6,4.6,7.8,y)
    for yy in (22.5,26.5,30.5): c.line((15.8,yy),(24.2,yy),1.4,bk)
    c.poly([(19,33.6),(21,33.6),(20,37.4)],bk)
    c.ell(20,15,3.8,3.6,bk); c.ell(20,14.6,3.2,3.0,yd)
    c.ell(20,9.6,3.8,3.2,y); c.ell(18,9,1.5,1.7,eye); c.ell(22,9,1.5,1.7,eye); c.ell(17.6,8.5,0.5,0.5,(255,220,220))
    for sd in (-1,1): c.poly_line([(20+sd*1.2,7),(20+sd*3,3.4),(20+sd*4.4,2.4)],0.7,bk)
    return c,[y,yd,bk,w,wh,wv,eye,(255,220,220)],(26,20,10)

# ---------------- HORNET (bigger, dark red-brown + orange, mandibles)
def hornet(t):
    c=Canvas(); o=(240,120,30); od=(150,52,20); rb=(92,30,24); w=(232,196,170); wh=(255,236,214); wv=(170,110,90); eye=(255,220,60)
    wings4(c,t,14,15,1.05,0.85,w,wh,wv,flap=(0.9,0.7,0.5,0.7))
    c.ell(20,26.5,6.0,9.4,rb); c.ell(20,26,5.3,8.8,o)
    for yy in (21.5,25.5,29.5): c.line((15,yy),(25,yy),1.6,rb)
    c.poly([(18.8,34.6),(21.2,34.6),(20,38.6)],rb)
    c.ell(20,14.6,4.6,4,rb); c.ell(20,14.2,3.9,3.3,od)
    c.ell(20,8.8,4.6,3.8,od); c.ell(20,8.4,3.9,3.1,o); c.ell(17.6,8,1.6,1.8,(40,20,10)); c.ell(22.4,8,1.6,1.8,(40,20,10))
    c.ell(17.4,7.4,0.6,0.6,eye); c.ell(22,7.4,0.6,0.6,eye)
    for sd in (-1,1): c.poly([(20+sd*1.0,5.4),(20+sd*3.4,3.0),(20+sd*1.8,1.6)],rb)
    return c,[o,od,rb,w,wh,wv,eye,(40,20,10)],(40,12,8)

# ---------------- MOTH (wide pale wings with orange eye-spots, feathery antennae)
def moth(t):
    c=Canvas(); wg=(226,212,240); wgd=(160,140,190); spot=(250,150,50); spd=(120,60,120); body=(120,96,140); fz=(200,186,220)
    k=[1.0,0.8,0.6,0.8][t]
    for sd in (-1,1):
        c.poly([(20+sd*2,13),(20+sd*16*k,7+ (1-k)*4),(20+sd*17*k,17),(20+sd*3,21)],wgd)
        c.poly([(20+sd*2,14),(20+sd*15*k,8.5+(1-k)*4),(20+sd*15.6*k,16.4),(20+sd*3,20)],wg)
        c.poly([(20+sd*2.5,21),(20+sd*12*k,23),(20+sd*9*k,31),(20+sd*3,27)],wgd)
        c.poly([(20+sd*2.8,21.6),(20+sd*11*k,23.4),(20+sd*8.4*k,29.6),(20+sd*3.2,26.4)],wg)
        c.ell(20+sd*10*k,13.4,2.8*k+0.4,2.6,spd); c.ell(20+sd*10*k,13.4,1.9*k+0.3,1.7,spot); c.ell(20+sd*9.6*k,13,0.6,0.6,(255,255,255))
        c.ell(20+sd*7*k,26,1.5*k+0.2,1.3,spot)
        for i in range(4): c.line((20+sd*1.2,8),(20+sd*(2.2+i*0.9),3.4+i*0.5),0.5,body)
        c.line((20+sd*1,8.4),(20+sd*5,3),0.6,body)
    c.ell(20,20,3.4,9.6,body); c.ell(20,19,2.6,8.6,fz); c.ell(20,10,3,2.6,body); c.ell(18.8,9.4,0.8,0.8,(30,20,40)); c.ell(21.2,9.4,0.8,0.8,(30,20,40))
    return c,[wg,wgd,spot,spd,body,fz,(255,255,255),(30,20,40)],(54,36,70)

# ---------------- DRAGONFLY (metallic cyan-green, long abdomen, 4 long veined wings)
def dragonfly(t):
    c=Canvas(); ab=(40,190,170); abd=(18,110,110); abl=(140,240,214); wg=(214,240,250); wv=(120,180,200); eye=(70,230,90); eyed=(20,120,50)
    k=[1.0,0.9,0.75,0.9][t]
    for sd in (-1,1):
        for ry,ln,ang in ((13,16,-0.15),(17,15,0.18)):
            L=ln*k; tx,ty=20+sd*L,ry+ang*L
            c.poly([(20+sd*2,ry-1),(tx-sd*2,ty-2.2),(tx,ty),(tx-sd*2,ty+1.6),(20+sd*2,ry+1)],wv)
            c.poly([(20+sd*2.4,ry-0.5),(tx-sd*2.4,ty-1.5),(tx-sd*0.8,ty),(tx-sd*2.4,ty+1.0),(20+sd*2.4,ry+0.5)],wg)
            c.line((20+sd*2,ry),(tx-sd*1,ty),0.5,wv)
    c.ell(20,15,3,4.2,abd); c.ell(20,14.6,2.4,3.6,ab)
    for i in range(6): c.ell(20+math.sin(t*math.pi/2+i*0.5)*0.3,20+i*3,1.7-i*0.1,1.9,abd); c.ell(20,19.6+i*3,1.2-i*0.08,1.4,ab if i%2 else abl)
    c.ell(17.4,9.4,2.6,2.4,eyed); c.ell(22.6,9.4,2.6,2.4,eyed); c.ell(17.2,9,2,1.8,eye); c.ell(22.4,9,2,1.8,eye); c.ell(16.6,8.4,0.6,0.6,(220,255,220))
    return c,[ab,abd,abl,wg,wv,eye,eyed,(220,255,220)],(10,50,50)

# ---------------- FIREFLY (dark beetle, big pulsing yellow-green glow)
def firefly(t):
    c=Canvas(); bd=(54,40,60); bl=(100,80,110); gl=[(200,255,80),(240,255,140),(255,255,210),(240,255,140)][t]; gl2=(120,220,40); hd=(240,90,60); wg=(200,210,230)
    k=[1.0,0.7,0.45,0.7][t]
    for sd in (-1,1):
        c.poly([(20+sd*2,13),(20+sd*12*k,10),(20+sd*12.4*k,16),(20+sd*2.6,18)],wg)
    c.ell(20,28,6.4+(t==2)*0.8,7+(t==2)*0.8,gl2); c.ell(20,28,5.2,5.8,gl); c.ell(18.6,26.6,1.6,1.4,(255,255,240))
    c.ell(20,18.5,5.4,6.4,bd); c.ell(18.8,17,1.8,3.4,bl); c.line((20,13),(20,24),0.6,(30,22,34))
    c.ell(20,10.6,3.6,3,hd); c.ell(20,10,2.6,1.6,bd); c.ell(18.6,9.8,0.7,0.7,(255,255,255)); c.ell(21.4,9.8,0.7,0.7,(255,255,255))
    for sd in (-1,1): c.poly_line([(20+sd*1.4,8),(20+sd*3.6,4),(20+sd*5,3.2)],0.6,bd)
    return c,[bd,bl,gl,gl2,hd,wg,(255,255,240),(255,255,255),(30,22,34)],(20,14,24)

# ---------------- HOVERBOT (saucer robot, glowing anti-grav ring, single eye)
def hoverbot(t):
    c=Canvas(); m0=(40,44,60); m1=(92,100,126); m2=(150,160,186); m3=(206,214,232); ring=[(70,220,255),(140,240,255),(70,220,255),(30,160,220)][t]; eye=(255,70,60)
    c.ell(20,21,15,15,m0); c.ell(20,21,14,14,ring); c.ell(20,21,12.4,12.4,m0)
    c.ell(20,20.4,11.6,11.6,m1); c.ell(18.6,18.6,9,9,m2); c.ell(17,16.4,4.4,3,m3)
    for k in range(6):
        a=k*math.pi/3+t*math.pi/12; c.ell(20+math.cos(a)*9.6,20.4+math.sin(a)*9.6,1.0,1.0,(255,210,60) if k%2==0 else (120,255,140))
    c.ell(20,12.6,4.4,3.4,m0); c.ell(20,12.2,3.6,2.6,eye); c.ell(19,11.6,1.0,0.8,(255,210,200))
    return c,[m0,m1,m2,m3,ring,eye,(255,210,200),(255,210,60),(120,255,140)],(14,16,26)

# ---------------- PROPELLER (orange quad-rotor drone, spinning prop discs)
def propeller(t):
    c=Canvas(); o=(250,140,40); od=(170,80,20); ol=(255,200,120); m0=(40,42,54); m1=(110,114,130); blur=(200,210,224); blade=(70,74,88)
    for sd_x,sd_y in ((-1,-1),(1,-1),(-1,1),(1,1)):
        cx,cy=20+sd_x*10.5,20+sd_y*10.5
        c.line((20,20),(cx,cy),2.4,m0); c.line((20,20),(cx,cy),1.2,m1)
        c.ell(cx,cy,6.4,6.4,blur); c.ell(cx,cy,5.4,5.4,(226,232,242))
        a=t*math.pi/4*(1 if sd_x*sd_y>0 else -1)
        c.line((cx+math.cos(a)*5.6,cy+math.sin(a)*5.6),(cx-math.cos(a)*5.6,cy-math.sin(a)*5.6),1.4,blade)
        c.ell(cx,cy,1.4,1.4,m0)
    c.ell(20,20,7,7.6,od); c.ell(20,19.6,6.2,6.8,o); c.ell(18.4,17.6,2.6,2.4,ol)
    c.ell(20,13.4,2.6,1.6,m0); c.ell(20,13.2,1.8,1.0,(90,230,255))
    return c,[o,od,ol,m0,m1,blur,blade,(226,232,242),(90,230,255)],(26,16,10)

# ---------------- STINGRAY (flat diamond, rippling edges, long tail)
def stingray(t):
    c=Canvas(); top=(70,96,170); topd=(36,52,110); topl=(120,150,214); spot=(180,206,250); belly=(220,230,250)
    pts=[]
    for i in range(13):
        a=math.pi*i/12; r=13+math.sin(a*3+t*math.pi/2)*1.3
        pts.append((20+math.cos(math.pi+a)*r*1.18, 20-math.sin(a)*r*0.82))
    c.poly([(20,3)]+pts[6:]+[(20,30)]+pts[:7],topd)
    inner=[(x*0.9+2,y*0.92+1.6) for x,y in pts]
    c.poly([(20,5)]+inner[6:]+[(20,28)]+inner[:7],top)
    c.poly_line([(20,29),(20+math.sin(t*math.pi/2)*1.6,34),(20-math.sin(t*math.pi/2)*1.2,38.4)],1.2,topd)
    c.ell(20,15,4,6,topl); 
    for (x,y) in ((12,17),(28,17),(15,22),(25,22),(20,24)): c.ell(x,y,1.0,1.0,spot)
    c.ell(17.6,9,1.0,1.0,(30,30,40)); c.ell(22.4,9,1.0,1.0,(30,30,40)); c.ell(17.4,8.7,0.4,0.4,(255,255,255))
    return c,[top,topd,topl,spot,belly,(30,30,40),(255,255,255)],(14,20,52)

# ---------------- SKY JELLY (pink/violet, yellow core, long drifting tentacles)
def sky_jelly(t):
    c=Canvas(); bd=(170,50,150); bm=(236,110,200); bl=(255,190,236); hi=(255,240,252); core=(255,220,80); ten=(250,150,220); tend=(170,60,160)
    for k in range(6):
        x0=12.5+k*3; pts=[]
        for i in range(7):
            pts.append((x0+math.sin(t*math.pi/2+i*0.8+k*1.3)*1.6,20+i*2.8))
        c.poly_line(pts,1.2,tend); c.poly_line(pts[:5],0.6,ten)
    c.ell(20,13,10.6,9.6,bd); c.ell(20,12.6,9.8,8.8,bm)
    for k in range(4): c.ell(20+[-5,-1.8,1.8,5][k],16.6,1.6,1.4,bd)
    c.ell(20,13,3.6,3.2,core); c.ell(20,12.6,2.0,1.8,(255,250,200)); c.ell(15.4,8.6,3.4,1.8,bl); c.ell(14.6,8,1.2,0.8,hi)
    return c,[bd,bm,bl,hi,core,ten,tend,(255,250,200)],(70,10,60)

NEW={"wasp":wasp,"hornet":hornet,"moth":moth,"dragonfly":dragonfly,"firefly":firefly,
     "hoverbot":hoverbot,"propeller":propeller,"stingray":stingray,"sky_jelly":sky_jelly}
for k,fn in NEW.items(): g.SPECIES[k]=("flier",fn)
FLIERS=["bat","wasp","moth","hornet","dragonfly","firefly","hoverbot","propeller","stingray","sky_jelly"]
