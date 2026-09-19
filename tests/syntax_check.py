#!/usr/bin/env python3
"""Parse every shipped .lua to catch syntax errors before they hit the client."""
import os, sys, glob
from luaparser import ast

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
targets = (glob.glob(os.path.join(root, "Bejeweled", "*.lua"))
           + glob.glob(os.path.join(root, "Arcade", "**", "*.lua"), recursive=True))
fails = 0
for path in sorted(targets):
    try:
        ast.parse(open(path, encoding="utf-8").read())
        print(f"  OK   {os.path.relpath(path, root)}")
    except Exception as e:
        fails += 1
        print(f"  FAIL {os.path.relpath(path, root)}: {e}")
print(f"syntax: {'ALL OK' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
