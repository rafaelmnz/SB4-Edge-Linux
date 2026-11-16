# Scratch scripts

One-off helpers written during development (kept so the work can be reviewed and repeated). They are not part of
the build. Most edit a kernel tree in place to add debug output or try a change:

- `edit*.py`, `undo-dbg.py`: msm DisplayPort / USB-C alt mode debugging edits to the kernel tree (see
  `docs/DEVELOPMENT-NOTES.md`, USB-C and DisplayPort sections).
- `wcd-patch.py`: WCD codec test edit.
- `catsearch.py`: search helper over extracted Windows driver catalogs.
- `vblank-rate.py`: measures the display's vblank rate (VRR test).
