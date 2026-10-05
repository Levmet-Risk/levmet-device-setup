"""Rebuild pinned offline packages. Run on a connected maintainer machine, not a new PC."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = [
    dict(id="gcloud", version="583.0.0", root="google-cloud-sdk",
         url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-583.0.0-windows-x86_64-bundled-python.zip"),
    dict(id="dbeaver", version="26.2.0", root="dbeaver",
         url="https://github.com/dbeaver/dbeaver/releases/download/26.2.0/dbeaver-ce-26.2.0-windows-x86_64.zip",
         expected="a2429b50e3e5ab0b5aeee4abea5bbbdae1968173996488fd592f43781058baca"),
    dict(id="codex", version="0.160.0", root="",
         url="https://github.com/openai/codex/releases/download/rust-v0.160.0/codex-x86_64-pc-windows-msvc.exe.zip",
         expected="aad5cf364c873b148e462b58fd06ad7b37fcab9b996be67133386b9322df26bb"),
]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def build(package):
    cache = ROOT / ".cache" / (package["id"] + ".zip")
    cache.parent.mkdir(exist_ok=True)
    if not cache.exists():
        request = urllib.request.Request(package["url"], headers={"User-Agent": "Levmet-device-setup"})
        partial = cache.with_suffix(".downloading")
        with urllib.request.urlopen(request, timeout=60) as source, partial.open("wb") as target:
            while data := source.read(1024 * 1024):
                target.write(data)
        partial.replace(cache)
    digest = sha(cache)
    if package.get("expected") and digest != package["expected"]:
        raise RuntimeError("Upstream checksum mismatch: " + package["id"])
    with zipfile.ZipFile(cache) as archive:
        bad = archive.testzip()
        if bad:
            raise RuntimeError("Corrupt archive member: " + bad)
        print(package["id"], "archive OK", "first entries:", archive.namelist()[:4], flush=True)
    folder = ROOT / "assets" / "packages" / package["id"]
    folder.mkdir(parents=True, exist_ok=True)
    parts = []
    with cache.open("rb") as source:
        index = 1
        while data := source.read(40 * 1024 * 1024):
            name = f"{package['id']}.zip.part{index:03}"
            target = folder / name
            target.write_bytes(data)
            parts.append(dict(path=target.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(data).hexdigest(), bytes=len(data)))
            index += 1
    # Remove only stale numbered parts in this package's explicitly resolved directory.
    current_names = {Path(part['path']).name for part in parts}
    for previous in folder.glob(package['id'] + '.zip.part[0-9][0-9][0-9]'):
        if previous.parent.resolve() != folder.resolve():
            raise RuntimeError('Unexpected package part path')
        if previous.name not in current_names:
            previous.unlink()
    return dict(id=package["id"], version=package["version"], archiveRoot=package["root"],
                source=package["url"], sha256=digest, bytes=cache.stat().st_size, parts=parts)


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=3) as pool:
        packages = list(pool.map(build, PACKAGES))
    manifest = ROOT / "assets" / "packages.json"
    manifest.write_text(json.dumps(dict(schemaVersion=1, architecture="windows-x86_64", packages=packages), indent=2) + "\n", encoding="utf-8")
    print("Wrote", manifest, flush=True)
