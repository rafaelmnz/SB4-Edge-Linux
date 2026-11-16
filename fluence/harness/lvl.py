import wave,struct,math,sys
for f in sys.argv[1:]:
    w=wave.open(f); n=w.getnframes(); c=w.getnchannels(); s=struct.unpack("<%dh"%(n*c),w.readframes(n))
    out=[]
    for ch in range(c):
        x=s[ch+c*4800::c]; r=math.sqrt(sum(v*v for v in x)/max(len(x),1)); out.append(round(20*math.log10(max(r,0.5)/32768),1))
    print(f, "ch dBFS:", out)
