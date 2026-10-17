"""Builds one zip per language in dist/.

    python build.py

Each zip holds an EchoTomeFinder/ folder ready to drop into Interface/AddOns.
The only difference between builds is the default language (players can still
switch with /etf lang) and the AddOns-list description in the .toc.
"""

import os
import re
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = "EchoTomeFinder"

LANGUAGES = {
    "en": {
        "notes": None,  # keep the English notes from the .toc
    },
    "fr": {
        "notes": "Repere les Tomes d'Echo dans les sacs, les banques et les jets de loot, "
                 "et indique lesquels de vos personnages les cherchent dans leurs builds.",
    },
}

EXTRA_FILES = ["README.md", "LICENSE"]


def read(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as f:
        return f.read()


def main():
    toc = read(ADDON + ".toc")
    version = re.search(r"^## Version: (.+)$", toc, re.M).group(1).strip()
    # Files listed in the .toc, in load order
    sources = [line.strip() for line in toc.splitlines()
               if line.strip() and not line.startswith("#")]

    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    for lang, opts in LANGUAGES.items():
        files = {}
        for name in sources + EXTRA_FILES:
            files[name] = read(name)

        locales = files["Locales.lua"]
        assert "ns.DefaultLanguage = nil" in locales
        files["Locales.lua"] = locales.replace(
            "ns.DefaultLanguage = nil", 'ns.DefaultLanguage = "%s"' % lang)

        if opts["notes"]:
            files[ADDON + ".toc"] = re.sub(
                r"^## Notes: .*$", "## Notes: " + opts["notes"], toc, flags=re.M)
        else:
            files[ADDON + ".toc"] = toc

        out = os.path.join(ROOT, "dist", "%s-%s-%s.zip" % (ADDON, version, lang))
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            for name, content in files.items():
                z.writestr(ADDON + "/" + name, content)
        print("built", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
