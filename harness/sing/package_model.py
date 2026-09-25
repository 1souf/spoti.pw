#!/usr/bin/env python3
"""Package the pinned two-second Core ML export as Sing.bundle for SING_MODEL_BUNDLE; never downloads a model."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path, help="the compiled separator.mlmodelc")
parser.add_argument("output", type=Path, help="new Sing.bundle directory, outside tracked source")
parser.add_argument("--unpinned", action="store_true",
                    help="accept an export made with other torch/coremltools versions (export_coreml.py "
                         "--unpinned-tools); check it against the goldens before use")
args = parser.parse_args()
source, output = args.model.resolve(), args.output.resolve()
if source.suffix != ".mlmodelc" or not source.is_dir() or output.exists() or output.name != "Sing.bundle":
    parser.error("need a compiled .mlmodelc and a new Sing.bundle output")
here = Path(__file__).resolve().parent
manifest = json.loads((here / "model.json").read_text())
profile = manifest["export"]
metadata = json.loads((source / "metadata.json").read_text())
if not isinstance(metadata, list) or len(metadata) != 1 or metadata[0].get("license") != "MIT":
    parser.error("the pinned model must retain its MIT metadata")
actual = {}
for name in profile["payloadHashes"]:
    with (source / name).open("rb") as stream:
        actual[name] = hashlib.file_digest(stream, "sha256").hexdigest()
if actual not in (profile["payloadHashes"], profile["referencePayloadHashes"]) and not args.unpinned:
    parser.error("Core ML graph or weights differ from the pinned exports (an unpinned export needs --unpinned)")
output.mkdir(parents=True)
try:
    # clonefile avoids duplicating model storage on APFS, with independent destination ownership.
    if sys.platform == "darwin":
        subprocess.run(["cp", "-cR", str(source), str(output / "separator.mlmodelc")], check=True)
    else:
        shutil.copytree(source, output / "separator.mlmodelc")
    (output / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "pw.spoti.sing-model",
        "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"}))
    for name in ("NOTICE", "model.json"):
        shutil.copyfile(here / name, output / name)
except BaseException:
    shutil.rmtree(output)
    raise
print(output)
