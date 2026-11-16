from PIL import Image
d="sb4edge/"; bg=Image.open(d+"background.png").convert("RGBA"); W,H=bg.size
T=360; S=120; gap=96
tiles=["os_ubuntu","os_windows"]; tw=len(tiles)*T+(len(tiles)-1)*gap
y=int(H*0.5-T*0.5); x=(W-tw)//2
for i,t in enumerate(tiles):
    px=x+i*(T+gap)
    if i==0: bg.alpha_composite(Image.open(d+"selection_big.png").convert("RGBA"),(px,y))
    bg.alpha_composite(Image.open(d+t+".png").convert("RGBA"),(px,y))
tools=["func_shutdown","func_reset","func_firmware"]; sg=40; sw=len(tools)*S+(len(tools)-1)*sg
sx=(W-sw)//2; sy=y+T+60
for i,t in enumerate(tools): bg.alpha_composite(Image.open(d+t+".png").convert("RGBA"),(sx+i*(S+sg),sy))
bg.convert("RGB").resize((1440,900),Image.LANCZOS).save("preview.png")
