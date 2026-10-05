"""Package clean application files from a known working Windows installation.

No user profiles or authentication stores are read. The Google SDK is exported
from a specified Git commit, rather than copied from a used working directory.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

from build_assets import ROOT, build


def repack_sdk(repository, commit):
    target = ROOT / ".cache" / "gcloud.zip"
    raw = ROOT / ".cache" / "gcloud-source.zip"
    subprocess.run(["git", "-C", str(repository), "archive", "--format=zip", "--prefix=google-cloud-sdk/",
                    "-o", str(raw), commit], check=True)
    with zipfile.ZipFile(raw) as source, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for item in source.infolist():
            # Bytecode caches are regenerated locally, and can embed the original
            # installation path in Python tracebacks. Ship only the source files.
            if '/__pycache__/' in item.filename or item.filename.endswith(('.pyc','.pyo','/.gitattributes')):
                continue
            output.writestr(item, source.read(item))
    return dict(id="gcloud", version="583.0.0", root="google-cloud-sdk",
                url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-583.0.0-windows-x86_64-bundled-python.zip",
                provenance="Clean SDK export from Levmet-Risk/gcloud-cli-portable commit " + commit + "; generated Python bytecode caches excluded")


def repack_dbeaver(home):
    allowed_files = [".eclipseproduct", "dbeaver.exe", "dbeaverc.exe", "dbeaver.ini", "readme.txt",
                     "configuration/config.ini", "configuration/org.eclipse.equinox.simpleconfigurator/bundles.info"]
    paths = [home / p for p in allowed_files]
    paths += list(home.glob("*.dll"))
    for name in ("features", "plugins", "licenses", "jre"):
        paths += [p for p in (home / name).rglob("*") if p.is_file()]
    with zipfile.ZipFile(ROOT / ".cache" / "dbeaver.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(set(paths)):
            archive.write(path, "dbeaver/" + path.relative_to(home).as_posix())
    return dict(id="dbeaver", version="26.2.0", root="dbeaver",
                url="https://github.com/dbeaver/dbeaver/releases/tag/26.2.0",
                provenance="Repacked installed Community distribution: application files and JRE only; no workspace, p2 state, logs, or user configuration")


def repack_codex(home, license_file):
    names = ["codex.exe", "codex-command-runner.exe", "codex-code-mode-host.exe",
             "codex-windows-sandbox-setup.exe", "codex-package.json", "rg.exe"]
    version = subprocess.check_output([str(home / "codex.exe"), "--version"], text=True).strip()
    with zipfile.ZipFile(ROOT / ".cache" / "codex.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in names:
            archive.write(home / name, name)
        archive.write(license_file, "LICENSE")
    return dict(id="codex", version=version.removeprefix("codex-cli "), root="",
                url="https://github.com/openai/codex",
                provenance="Repacked Codex CLI binaries and companion tools from the installed official OpenAI VS Code extension; no extension UI, account data, or settings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gcloud-repository", type=Path, required=True)
    parser.add_argument("--gcloud-commit", required=True)
    parser.add_argument("--dbeaver-home", type=Path, required=True)
    parser.add_argument("--codex-bin", type=Path, required=True)
    parser.add_argument("--codex-license", type=Path, required=True)
    args = parser.parse_args()
    (ROOT / ".cache").mkdir(exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(repack_sdk, args.gcloud_repository, args.gcloud_commit),
                   pool.submit(repack_dbeaver, args.dbeaver_home),
                   pool.submit(repack_codex, args.codex_bin, args.codex_license)]
        packages = []
        for future in futures:
            definition = future.result()
            package = build(definition)
            package["provenance"] = definition["provenance"]
            packages.append(package)
    (ROOT / "assets" / "packages.json").write_text(json.dumps(dict(schemaVersion=1, architecture="windows-x86_64", packages=packages), indent=2) + "\n", encoding="utf-8")
    print("Offline packages complete", flush=True)
