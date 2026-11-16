"""Run the exact upstream A2UI generator before the Xcode 27.2 app graph consumes outputs.

Xcode's large app graph advertised plugin outputs without scheduling their commands in
run 43841684109. This uses the identical original executable source, arguments and inputs;
it does not replace a schema, parser, catalog, validator or renderer.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

PIN = "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"
GENERATOR = "swift/core/Tools/A2UISchemaGenerator/A2UISchemaGenerator.swift"
GENERATOR_SHA256 = "0d39e7e6ebdf922847bb82679250dc2ac67132d0515002055e3a0563b1bea972"
INPUTS = ["specification/v0_9_1/json/" + name + ".json" for name in
          ["common_types", "server_to_client", "client_to_server", "client_capabilities"]]
INPUTS += ["specification/v0_9_1/catalogs/basic/catalog.json"]
INPUTS += ["specification/v1_0/json/" + name + ".json" for name in
           ["common_types", "catalog_definition", "agent_to_renderer", "renderer_to_agent", "renderer_capabilities"]]
INPUTS += ["catalogs/basic/v1/catalog.json"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-packages-path", type=Path, required=True)
    parser.add_argument("--derived-data-path", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    started = time.monotonic()
    source = (args.source_packages_path / "checkouts/a2ui").resolve()
    derived = args.derived_data_path.resolve()
    args.evidence.mkdir(parents=True, exist_ok=True)
    def run(command, **options):
        return subprocess.check_output([str(value) for value in command], timeout=120, **options)
    assert run(["git", "-C", source, "rev-parse", "HEAD"]).decode().strip() == PIN
    records = {}
    for name in [GENERATOR, *INPUTS]:
        data = (source / name).read_bytes()
        assert data == run(["git", "-C", source, "show", "HEAD:" + name]), name
        records[name] = sha(data)
    assert records[GENERATOR] == GENERATOR_SHA256
    compiler = run(["xcrun", "--find", "swiftc"]).decode().strip()
    sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).decode().strip()
    outputs = {}
    with tempfile.TemporaryDirectory(prefix="hanlin-original-a2ui-generator-") as folder:
        scratch = Path(folder)
        executable = scratch / "A2UISchemaGenerator"
        compile_command = [compiler, "-parse-as-library", "-sdk", sdk, source / GENERATOR, "-o", executable]
        with (args.evidence / "compiler.log").open("wb") as log:
            subprocess.run([str(value) for value in compile_command], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        for target, name in [("A2UIJSON", "GeneratedA2UIJSONSchemas.swift"), ("BasicCatalog", "GeneratedBasicCatalogComponents.swift")]:
            generated = scratch / name
            run([executable, "--target", target, "--repo-root", source, "--output", generated])
            data = generated.read_bytes()
            assert data and b"import " in data
            destination = derived / "Build/Intermediates.noindex/BuildToolPluginIntermediates/a2ui.output" / target / "A2UISchemaGeneratorPlugin" / name
            assert destination.is_relative_to(derived)
            destination.parent.mkdir(parents=True, exist_ok=True)
            changed = not destination.exists() or destination.read_bytes() != data
            if changed:
                destination.write_bytes(data)
            outputs[target] = {"path": str(destination), "sha256": sha(data), "bytes": len(data), "updated": changed}
    proof = {"status": "ORIGINAL_GENERATOR_EXECUTED", "revision": PIN, "inputs": records,
             "compiler": compiler, "sdk": sdk, "outputs": outputs, "seconds": time.monotonic() - started}
    (args.evidence / "result.json").write_text(json.dumps(proof, indent=2))
    print(json.dumps(proof, indent=2))


if __name__ == "__main__":
    main()
