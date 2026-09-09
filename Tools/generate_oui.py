#!/usr/bin/env python3
"""Build Vaktpost's compact offline MAC vendor index from IEEE CSV files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import struct
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


SOURCES = (
    ("IAB", 36, "https://standards-oui.ieee.org/iab/iab.csv"),
    ("MA-L", 24, "https://standards-oui.ieee.org/oui/oui.csv"),
    ("MA-M", 28, "https://standards-oui.ieee.org/oui28/mam.csv"),
    ("MA-S", 36, "https://standards-oui.ieee.org/oui36/oui36.csv"),
)
REGISTRY_CODE = {"MA-L": 0, "MA-M": 1, "MA-S": 2, "IAB": 3}
MAGIC = b"VKIEEE01"


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "Vaktpost OUI database builder/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def parse_csv(payload: bytes, registry: str, bits: int) -> list[tuple[int, int, str, int]]:
    text = payload.decode("utf-8-sig")
    records: list[tuple[int, int, str, int]] = []
    for row in csv.DictReader(io.StringIO(text)):
        assignment = "".join(character for character in row.get("Assignment", "") if character.isalnum())
        vendor = " ".join(row.get("Organization Name", "").split())
        if len(assignment) != bits // 4 or not vendor:
            continue
        records.append((bits, int(assignment, 16), vendor, REGISTRY_CODE[registry]))
    return records


def build(output: Path, manifest: Path) -> None:
    # Later registries win an exact duplicate. MA-S replaced IAB, so this keeps
    # the current assignment if the legacy and current files ever overlap.
    combined: dict[tuple[int, int], tuple[str, int]] = {}
    source_notes: list[tuple[str, str, int, int, str]] = []
    for registry, bits, url in SOURCES:
        payload = download(url)
        parsed = parse_csv(payload, registry, bits)
        for record_bits, prefix, vendor, code in parsed:
            combined[(record_bits, prefix)] = (vendor, code)
        source_notes.append((registry, url, len(payload), len(parsed), hashlib.sha256(payload).hexdigest()))

    vendors = sorted({vendor for vendor, _ in combined.values()})
    strings = bytearray()
    offsets: dict[str, int] = {}
    for vendor in vendors:
        offsets[vendor] = len(strings)
        strings.extend(vendor.encode("utf-8"))
        strings.append(0)

    entries = bytearray()
    for (bits, prefix), (vendor, registry_code) in sorted(combined.items()):
        entries.extend(struct.pack("<BQIB", bits, prefix, offsets[vendor], registry_code))

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(struct.pack("<8sII", MAGIC, len(combined), len(strings)) + entries + strings)

    lines = [
        "# Offline IEEE MAC assignment data",
        "",
        f"Generated: {datetime.now(timezone.utc).isoformat(timespec='seconds')}",
        f"Records: {len(combined):,}",
        f"Vendors: {len(vendors):,}",
        f"Binary size: {output.stat().st_size:,} bytes",
        "",
        "The app bundles only assignment prefixes, registry types, and organization names.",
        "Regenerate with `make oui` before a release to retrieve the current public IEEE listings.",
        "",
        "| Registry | Source | CSV bytes | Rows | SHA-256 |",
        "|---|---|---:|---:|---|",
    ]
    for registry, url, size, count, digest in source_notes:
        lines.append(f"| {registry} | {url} | {size:,} | {count:,} | `{digest}` |")
    lines += [
        "",
        "Source: IEEE Registration Authority public listings.",
        "https://standards.ieee.org/products-programs/regauth/",
        "",
    ]
    manifest.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    arguments = parser.parse_args()
    build(arguments.output, arguments.manifest)


if __name__ == "__main__":
    main()
