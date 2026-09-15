#!/usr/bin/env python3
"""Check the exported image's layer sizes and bundled model without loading it."""
import json
import sys
import tarfile

layers = []
weights = {}
with tarfile.open(sys.argv[1], mode="r|*") as archive:
    for member in archive:
        if not member.name.endswith(".tar"):
            continue
        if member.size >= 10_000_000_000:
            raise SystemExit(f"Layer exceeds GHCR's limit: {member.name} ({member.size} bytes)")
        layers.append(member.size)
        with tarfile.open(fileobj=archive.extractfile(member), mode="r|*") as layer:
            for entry in layer:
                if entry.isfile() and entry.name.endswith(".gguf"):
                    filename = entry.name.rsplit("/", 1)[-1]
                    if filename in weights:
                        raise SystemExit(f"Duplicate weights: {filename}")
                    weights[filename] = entry.size

expected = {f"qwen-{i:05d}-of-00005.gguf" for i in range(1, 6)}
if set(weights) != expected:
    raise SystemExit(f"Expected five Qwen shards, found: {sorted(weights)}")
if not 16_000_000_000 < sum(weights.values()) < 17_000_000_000:
    raise SystemExit(f"Unexpected bundled model size: {sum(weights.values())}")
print(json.dumps({"layers": len(layers), "largest_layer_bytes": max(layers), "weights": weights}, indent=2))
