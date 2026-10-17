"""Builds the release zip in dist/.

    python build.py

The zip holds an EchoTomeFinder/ folder ready to drop into Interface/AddOns.
"""

import os
import re
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = "EchoTomeFinder"
EXTRA_FILES = ["README.md", "LICENSE"]


def main():
    toc_path = os.path.join(ROOT, ADDON + ".toc")
    with open(toc_path, encoding="utf-8") as f:
        toc = f.read()
    version = re.search(r"^## Version: (.+)$", toc, re.M).group(1).strip()
    # Files listed in the .toc, in load order
    sources = [line.strip() for line in toc.splitlines()
               if line.strip() and not line.startswith("#")]

    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", "%s-%s.zip" % (ADDON, version))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in [ADDON + ".toc"] + sources + EXTRA_FILES:
            z.write(os.path.join(ROOT, name), ADDON + "/" + name)
    print("built", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
