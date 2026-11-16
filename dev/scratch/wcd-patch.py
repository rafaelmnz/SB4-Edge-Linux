p = "wcd938x.c"
s = open(p).read()
old = "\tif (jack)\n\t\treturn wcd_mbhc_start(wcd->wcd_mbhc, &wcd->mbhc_cfg, jack);"
new = ("\tif (!wcd->wcd_mbhc) {\n"
       "\t\tdev_warn(comp->dev, \"set_jack before codec probe, no jack detection\\n\");\n"
       "\t\treturn -ENOTSUPP;\n\t}\n" + old)
assert old in s
open(p, "w").write(s.replace(old, new))
