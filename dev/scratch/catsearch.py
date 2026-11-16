import re,html,sys,urllib.parse,urllib.request
q=sys.argv[1]
req=urllib.request.Request("https://www.catalog.update.microsoft.com/Search.aspx?q="+urllib.parse.quote(q),headers={"User-Agent":"Mozilla/5.0"})
s=urllib.request.urlopen(req,timeout=60).read().decode("utf-8","ignore")
n=0
for m in re.finditer(r'<tr id="([0-9a-f-]{36})_R\d+"(.*?)</tr>',s,re.S):
    cells=[re.sub(r"\s+"," ",html.unescape(re.sub(r"<[^>]+>","",c))).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>",m.group(2),re.S)]
    cells=[c for c in cells if c]
    print(m.group(1)," | ".join([cells[0],cells[2],cells[3],cells[4],cells[5]] if len(cells)>5 else cells)); n+=1
print("#",q,n)
