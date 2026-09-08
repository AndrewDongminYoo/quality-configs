#!/usr/bin/env python3
import json
import sys


def normalize_locations(sarif: dict, target: str) -> dict:
    """Map Grype's virtual single-file locations to the repository target."""
    for run in sarif.get("runs", []):
        for result in run.get("results", []):
            for location in result.get("locations", []):
                artifact = location.get("physicalLocation", {}).get(
                    "artifactLocation"
                )
                if artifact is not None:
                    artifact["uri"] = target
    return sarif


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: grype_to_sarif.py <target>", file=sys.stderr)
        return 2

    sarif = json.load(sys.stdin)
    json.dump(normalize_locations(sarif, sys.argv[1]), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
