"""Build the KUAL bundle from the runtime and the shared, device-tested helpers."""
import hashlib
import json
from pathlib import Path
import shutil

BASE = Path(__file__).resolve().parent
OUTPUT = BASE.parent / "build/kindle-weather"
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT / "lib").mkdir(exist_ok=True)
for name in ("run.sh", "start.sh", "stop.sh", "config.xml", "menu.json", "prepare.png"):
    shutil.copyfile(BASE / "dashboard" / name, OUTPUT / name)
for name in ("alarm.sh", "fetch.sh", "validate.sh", "keywatch.sh"):
    shutil.copyfile(BASE / "weather-test" / name, OUTPUT / "lib" / name)
for path in OUTPUT.rglob("*.sh"):
    path.chmod(0o755)
files = {str(p.relative_to(OUTPUT)): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in sorted(OUTPUT.rglob("*")) if p.is_file() and p.name != "bundle-manifest.json"}
(OUTPUT / "bundle-manifest.json").write_text(json.dumps(files, indent=2) + "\n")
print(OUTPUT)
