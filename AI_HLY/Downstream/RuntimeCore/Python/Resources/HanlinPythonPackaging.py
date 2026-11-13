"""Standards-based package operations for the embedded interpreter.

packaging/resolvelib/installer/pyproject-hooks are checksum-pinned resources.
PEP 517 hooks use the public custom runner contract in-process: iOS has no
subprocess. Backends requiring a compiler/process must report that real failure.
"""
import contextlib
import dataclasses
import email
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import sys
import tarfile
import tempfile
import tomllib
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile


def bootstrap(resources):
    for item in resources:
        path = Path(item["path"])
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if digest != item["sha256"]:
            raise ValueError("Bundled packaging dependency failed SHA-256: " + path.name)
        sys.path.insert(0, str(path))


@contextlib.contextmanager
def preserved_interpreter_state():
    previous = os.getcwd(), sys.argv[:], sys.path[:], dict(os.environ), dict(sys.modules)
    try:
        yield
    finally:
        os.chdir(previous[0])
        sys.argv[:] = previous[1]
        sys.path[:] = previous[2]
        os.environ.clear()
        os.environ.update(previous[3])
        for name in list(sys.modules):
            if name not in previous[4]:
                sys.modules.pop(name, None)
        sys.modules.update(previous[4])


def in_process_hook(command, cwd=None, extra_environ=None):
    with preserved_interpreter_state():
        if cwd:
            os.chdir(cwd)
        os.environ.update(extra_environ or {})
        sys.argv[:] = command[1:]
        try:
            runpy.run_path(command[1], run_name="__main__")
        except SystemExit as error:
            if error.code not in (None, 0):
                raise RuntimeError("PEP 517 backend exited with " + str(error.code)) from error


def safe_extract(archive, destination):
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as source:
            for entry in source.infolist():
                path = (destination / entry.filename.replace("\\", "/")).resolve()
                if not path.is_relative_to(destination) or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError("Source archive escapes its staging directory")
            source.extractall(destination)
    else:
        with tarfile.open(archive) as source:
            source.extractall(destination, filter="data")
    children = list(destination.iterdir())
    return children[0] if len(children) == 1 and children[0].is_dir() else destination


@dataclasses.dataclass(frozen=True)
class Candidate:
    name: str
    version: object
    extras: frozenset
    wheel: str
    sha256: str
    requirements: tuple
    summary: str
    origin: str
    pure: bool


class Repository:
    def __init__(self, request):
        from packaging.markers import default_environment
        from packaging.tags import sys_tags
        self.request = request
        self.root = Path(request["workspace"]).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.index = request.get("indexURL", "https://pypi.org").rstrip("/")
        self.environment = default_environment()
        self.tags = frozenset(sys_tags())
        self.projects = {}
        self.prepared = {}
        self.building = set()
        self.bundled = {}
        for extension in request.get("nativeExtensions", []):
            # Only a provider actually registered by this signed app can satisfy
            # a bundled-native dependency; a JSON claim or downloaded .so cannot.
            if extension["module"] not in sys.builtin_module_names:
                continue
            module = __import__(extension["module"])
            actual = next((e for e in module.registry() if e["module"] == extension["module"] and e["distribution"] == extension["distribution"]), None)
            if actual and actual["version"] == extension["version"] and (actual["pythonMajor"], actual["pythonMinor"]) == sys.version_info[:2]:
                self.bundled[extension["distribution"]] = extension

    def json(self, url):
        if url not in self.projects:
            try:
                with urllib.request.urlopen(url) as response:
                    self.projects[url] = json.load(response)
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise
                # A missing dependency is an empty candidate set. The standards
                # resolver may choose an older parent instead; transport/TLS and
                # server failures must still propagate as actual failures.
                error.close()
                self.projects[url] = {"releases": {}}
        return self.projects[url]

    def download(self, url, digest=None):
        parsed = urllib.parse.urlsplit(url)
        fragment = urllib.parse.parse_qs(parsed.fragment)
        expected = digest or fragment.get("sha256", [None])[0]
        if parsed.scheme in ("", "file"):
            source = Path(urllib.request.url2pathname(parsed.path) if parsed.scheme else url)
            if source.is_dir():
                return source, None
            name = source.name
        else:
            name = Path(urllib.parse.unquote(parsed.path)).name
        if not name:
            raise ValueError("Package source has no file name")
        folder = self.root / "downloads" / (expected or hashlib.sha256(url.encode()).hexdigest())
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        if not target.exists():
            partial = folder / (name + ".partial-" + uuid.uuid4().hex)
            try:
                limit = self.request.get("maximumArtifactBytes")
                if limit is not None and (not isinstance(limit, int) or limit < 1):
                    raise ValueError("An explicit artifact byte budget must be positive")
                incoming = source.open("rb") if parsed.scheme in ("", "file") else urllib.request.urlopen(urllib.parse.urlunsplit(parsed._replace(fragment="")))
                with incoming, partial.open("wb") as output:
                    count = 0
                    while chunk := incoming.read(65536):
                        count += len(chunk)
                        if limit is not None and count > limit:
                            raise ValueError("Package exceeds the caller's explicit artifact byte budget")
                        output.write(chunk)
                partial.replace(target)
            finally:
                partial.unlink(missing_ok=True)
        with target.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        limit = self.request.get("maximumArtifactBytes")
        if limit is not None and target.stat().st_size > limit:
            raise ValueError("Package exceeds the caller's explicit artifact byte budget")
        if expected and actual.lower() != expected.lower():
            target.unlink(missing_ok=True)
            raise ValueError("Package download failed SHA-256: " + name)
        return target, actual

    def build_wheel(self, source):
        from pyproject_hooks import BuildBackendHookCaller
        source = Path(source).resolve()
        key = str(source)
        if key in self.building:
            raise ValueError("Cyclic PEP 517 build dependency: " + key)
        self.building.add(key)
        try:
            if source.is_file():
                source = safe_extract(source, self.root / "sources" / uuid.uuid4().hex)
            project = source / "pyproject.toml"
            config = tomllib.loads(project.read_text()) if project.exists() else {}
            build = config.get("build-system", {"requires": ["setuptools>=40.8.0"], "build-backend": "setuptools.build_meta:__legacy__"})
            backend = build.get("build-backend", "setuptools.build_meta:__legacy__")
            environment = self.root / "build-env" / uuid.uuid4().hex
            with preserved_interpreter_state():
                self.install(self.resolve(build.get("requires", [])), environment)
                sys.path.insert(0, str(environment))
                hooks = BuildBackendHookCaller(str(source), backend, backend_path=build.get("backend-path"), runner=in_process_hook)
                extra = hooks.get_requires_for_build_wheel({})
                if extra:
                    self.install(self.resolve(extra), environment, overwrite=True)
                wheels = self.root / "built" / uuid.uuid4().hex
                wheels.mkdir(parents=True)
                name = hooks.build_wheel(str(wheels), {})
                result = (wheels / name).resolve()
                if not result.is_relative_to(wheels.resolve()) or not result.is_file():
                    raise ValueError("Build backend returned an invalid wheel path")
                return result
        finally:
            self.building.remove(key)

    def prepare(self, url, expected=None, extras=frozenset()):
        from packaging.requirements import Requirement
        from packaging.utils import canonicalize_name, parse_wheel_filename
        from packaging.version import Version
        from packaging.specifiers import SpecifierSet
        key = url, expected
        if key not in self.prepared:
            archive, _ = self.download(url, expected)
            wheel = archive if archive.suffix == ".whl" else self.build_wheel(archive)
            _, _, _, tags = parse_wheel_filename(wheel.name)
            if not tags.intersection(self.tags):
                raise IncompatibleDistribution("Wheel tags do not match this interpreter: " + wheel.name)
            with zipfile.ZipFile(wheel) as source:
                metadata_files = [n for n in source.namelist() if n.endswith(".dist-info/METADATA") and n.count("/") == 1]
                if len(metadata_files) != 1:
                    raise ValueError("Wheel must contain exactly one METADATA file")
                metadata = email.message_from_bytes(source.read(metadata_files[0]))
                requires_python = metadata.get("Requires-Python", "")
                if requires_python and not SpecifierSet(requires_python).contains(self.environment["python_full_version"], prereleases=True):
                    raise IncompatibleDistribution("Requires-Python does not match the running interpreter")
            with wheel.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            candidate = Candidate(canonicalize_name(metadata["Name"]), Version(metadata["Version"]), frozenset(),
                str(wheel), digest, tuple(metadata.get_all("Requires-Dist", [])), metadata.get("Summary", ""), url,
                all(tag.abi == "none" and tag.platform == "any" for tag in tags))
            # Validate every dependency using the standard grammar before exposing it to the resolver.
            for raw in candidate.requirements:
                Requirement(raw)
            self.prepared[key] = candidate
        return dataclasses.replace(self.prepared[key], extras=frozenset(extras))

    def matches(self, name, requirements):
        from packaging.specifiers import SpecifierSet
        from packaging.utils import parse_wheel_filename
        from packaging.version import Version, InvalidVersion
        extras = frozenset(extra for requirement in requirements for extra in requirement.extras)
        urls = {requirement.url for requirement in requirements if requirement.url}
        if len(urls) > 1:
            return
        if urls:
            try:
                yield self.prepare(next(iter(urls)), extras=extras)
            except IncompatibleDistribution:
                return
            return
        if name in self.bundled:
            extension = self.bundled[name]
            yield self.prepare(Path(extension["path"]).as_uri(), extension["sha256"], extras)
            return
        project = self.json(self.index + "/pypi/" + urllib.parse.quote(name, safe="") + "/json")
        specifier = SpecifierSet(",".join(str(requirement.specifier) for requirement in requirements if str(requirement.specifier)))
        releases = {}
        for raw, files in project.get("releases", {}).items():
            try:
                releases[Version(raw)] = files
            except InvalidVersion:
                continue
        versions = sorted(specifier.filter(releases), reverse=True)
        for version in versions:
            files = releases[version]
            compatible, sources = [], []
            for file in files:
                if file.get("yanked") and not any(str(r.specifier) in ("==" + str(version), "===" + str(version)) for r in requirements):
                    continue
                if file.get("requires_python") and not SpecifierSet(file["requires_python"]).contains(self.environment["python_full_version"], prereleases=True):
                    continue
                if file.get("packagetype") == "bdist_wheel":
                    try:
                        if parse_wheel_filename(file["filename"])[3].intersection(self.tags):
                            compatible.append(file)
                    except ValueError:
                        continue
                elif file.get("packagetype") == "sdist":
                    sources.append(file)
            for file in compatible + sources:
                expected = file.get("digests", {}).get("sha256")
                if not expected:
                    raise ValueError("Package index artifact has no SHA-256 integrity metadata")
                try:
                    candidate = self.prepare(file["url"], expected, extras)
                except IncompatibleDistribution:
                    continue
                if candidate.name != name or candidate.version != version:
                    raise ValueError("Distribution metadata disagrees with the index")
                yield candidate

    def resolve(self, raw_requirements):
        from packaging.requirements import Requirement
        from resolvelib import Resolver, BaseReporter
        from resolvelib.resolvers import ResolutionTooDeep
        requirements = [Requirement(raw) for raw in raw_requirements]
        requirements = [r for r in requirements if r.marker is None or r.marker.evaluate({**self.environment, "extra": ""})]
        rounds = 256
        while True:
            try:
                return Resolver(Provider(self), BaseReporter()).resolve(requirements, max_rounds=rounds).mapping
            except ResolutionTooDeep:
                # Library iteration batching is not an installation permission/cap.
                # Retry with cached artifacts and a larger batch until solved or cancelled.
                rounds *= 2

    def install(self, candidates, destination, overwrite=False):
        from installer import install
        from installer.destinations import SchemeDictionaryDestination
        from installer.sources import WheelFile
        destination = Path(destination).resolve()
        destination.mkdir(parents=True, exist_ok=True)
        scheme = {name: str(destination) for name in ("purelib", "platlib", "headers", "data")}
        scheme["scripts"] = str(destination / "bin")
        target = SchemeDictionaryDestination(scheme, sys.executable or "python3", "posix", overwrite_existing=overwrite)
        for candidate in candidates.values():
            print("Installing", candidate.name, candidate.version, flush=True)
            with WheelFile.open(candidate.wheel) as source:
                source.validate_record()
                install(source, target, {"INSTALLER": b"Hanlin standards packaging\n"})


class IncompatibleDistribution(ValueError):
    pass


# Construct the public resolvelib provider only after checksum-verified bootstrap.
def make_provider():
    from resolvelib.providers import AbstractProvider
    from packaging.requirements import Requirement
    from packaging.utils import canonicalize_name

    class StandardsProvider(AbstractProvider):
        def __init__(self, repository):
            self.repository = repository

        def identify(self, requirement_or_candidate):
            return canonicalize_name(requirement_or_candidate.name)

        def get_preference(self, identifier, resolutions, candidates, information, backtrack_causes):
            return identifier

        def find_matches(self, identifier, requirements, incompatibilities):
            requested = list(requirements[identifier])
            rejected = set(incompatibilities[identifier])
            # A factory is resolvelib's public lazy-candidate contract. Returning
            # an ordinary generator eagerly materializes every release in 1.2.1.
            def candidates():
                return (candidate for candidate in self.repository.matches(identifier, requested)
                        if candidate not in rejected and all(self.is_satisfied_by(r, candidate) for r in requested))
            return candidates

        def is_satisfied_by(self, requirement, candidate):
            return self.identify(requirement) == candidate.name and requirement.specifier.contains(candidate.version, prereleases=True) and requirement.extras.issubset(candidate.extras)

        def get_dependencies(self, candidate):
            result = []
            for raw in candidate.requirements:
                requirement = Requirement(raw)
                if requirement.marker is None or any(requirement.marker.evaluate({**self.repository.environment, "extra": extra}) for extra in candidate.extras | {""}):
                    result.append(requirement)
            return result
    return StandardsProvider


def run(request):
    global Provider
    with preserved_interpreter_state():
        bootstrap(request["resources"])
        Provider = make_provider()
        repository = Repository(request)
        source = request["requirement"].strip()
        if Path(source).exists():
            candidate = repository.prepare(Path(source).resolve().as_uri())
            source = candidate.name + " @ " + Path(source).resolve().as_uri()
        from packaging.requirements import Requirement
        root = Requirement(source)
        if request.get("version"):
            if root.url:
                raise ValueError("An explicit version cannot be combined with a direct source URL")
            from packaging.specifiers import SpecifierSet
            root.specifier = SpecifierSet(",".join(filter(None, (str(root.specifier), "==" + request["version"]))))
            source = str(root)
        graph = repository.resolve([source])
        from packaging.utils import canonicalize_name
        name = canonicalize_name(root.name)
        if name not in graph:
            raise ValueError("The root requirement does not apply to this interpreter")
        if request.get("destination"):
            repository.install(graph, request["destination"])
        def record(candidate):
            result = {"name": candidate.name, "version": str(candidate.version), "wheelFileName": Path(candidate.wheel).name,
                    "sha256": candidate.sha256, "requirements": list(candidate.requirements), "summary": candidate.summary,
                    "pure": candidate.pure, "origin": candidate.origin}
            if candidate.name in repository.bundled:
                result["importName"] = repository.bundled[candidate.name]["importName"]
            return result
        return {"root": record(graph[name]), "dependencies": [record(c) for key, c in graph.items() if key != name],
                "interpreter": {"version": sys.version, "platform": sys.platform, "tags": sorted(map(str, repository.tags))}}
