#!/usr/bin/env python3
"""Dependency-aware affected-tests CI routing planner for hanlin-ai.

Determines the comparison base SHA, head SHA, changed files, affected logical
components, transitive consumers, and required validation groups.

NON-NEGOTIABLE RULE: Full validation is NEVER selected automatically.
If changed paths cannot be mapped, or if comparison base cannot be established,
the planner FAILS with an actionable error.
"""

from __future__ import annotations

import argparse
import collections
import fnmatch
import json
import os
import pathlib
import subprocess
import sys
from typing import Any, Dict, List, Optional, Set, Tuple


class RoutingError(Exception):
    """Base exception for CI routing failures."""


class UnmappedPathsError(RoutingError):
    """Raised when one or more changed files do not match any known rule."""

    def __init__(self, unmapped_paths: List[str]) -> None:
        super().__init__(
            f"Affected-test routing is incomplete. {len(unmapped_paths)} unmapped path(s)."
        )
        self.unmapped_paths = unmapped_paths


class BaseSHAResolutionError(RoutingError):
    """Raised when a trustworthy comparison base SHA cannot be established."""

    def __init__(
        self,
        attempted_method: str,
        head_sha: str,
        candidate_shas: List[str],
        reason: str,
    ) -> None:
        super().__init__(
            f"Could not establish comparison base SHA for {head_sha}: {reason}"
        )
        self.attempted_method = attempted_method
        self.head_sha = head_sha
        self.candidate_shas = candidate_shas
        self.reason = reason


def match_pattern(path_str: str, pattern: str) -> bool:
    """Match a POSIX relative path against a glob pattern.

    Supports:
    - 'path/to/dir/**' (prefix matching directory and all contents)
    - '**/*.ext' (matching suffix across any subdirectories)
    - '*.ext' (standard fnmatch)
    - exact file paths
    """
    normalized_path = path_str.replace("\\", "/")
    normalized_pattern = pattern.replace("\\", "/")

    if normalized_pattern.endswith("/**"):
        prefix = normalized_pattern[:-3]
        if not any(c in prefix for c in "*?["):
            return normalized_path == prefix or normalized_path.startswith(prefix + "/")

    pure_path = pathlib.PurePosixPath(normalized_path)
    if pure_path.match(normalized_pattern):
        return True

    if fnmatch.fnmatch(normalized_path, normalized_pattern):
        return True

    return False


def run_git(args: List[str], cwd: pathlib.Path) -> str:
    """Run a git command and return stripped stdout."""
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed with code {result.returncode}:\n{result.stderr.strip()}"
        )
    return result.stdout.strip()


def git_commit_exists(sha: str, cwd: pathlib.Path) -> bool:
    """Check if a commit exists in local git repository."""
    if not sha or sha == "0000000000000000000000000000000000000000":
        return False
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
        cwd=cwd,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def fetch_commit_if_needed(sha: str, cwd: pathlib.Path) -> bool:
    """Attempt shallow fetch of a specific commit from origin if missing."""
    if git_commit_exists(sha, cwd):
        return True
    try:
        run_git(["fetch", "origin", sha, "--depth=1"], cwd=cwd)
        return git_commit_exists(sha, cwd)
    except Exception:
        return False


def resolve_comparison_range(
    repo_root: pathlib.Path,
    event_name: str,
    event_payload: Dict[str, Any],
    compare_base_sha_input: Optional[str] = None,
    head_sha_input: Optional[str] = None,
) -> Tuple[str, str]:
    """Resolve the (base_sha, head_sha) comparison range.

    NEVER returns a guess that could miss commits without reporting an error.
    """
    head_sha = head_sha_input
    if not head_sha:
        try:
            head_sha = run_git(["rev-parse", "HEAD"], cwd=repo_root)
        except Exception as err:
            head_sha = os.environ.get("GITHUB_SHA", "")
            if not head_sha:
                raise BaseSHAResolutionError(
                    attempted_method="rev-parse HEAD",
                    head_sha="unknown",
                    candidate_shas=[],
                    reason=f"Failed to determine HEAD commit: {err}",
                )

    # 1. Explicit compare_base_sha override
    if compare_base_sha_input and compare_base_sha_input.strip():
        explicit_base = compare_base_sha_input.strip()
        if not git_commit_exists(explicit_base, repo_root):
            if not fetch_commit_if_needed(explicit_base, repo_root):
                raise BaseSHAResolutionError(
                    attempted_method="explicit compare_base_sha input",
                    head_sha=head_sha,
                    candidate_shas=[explicit_base],
                    reason=f"Explicit base SHA '{explicit_base}' does not exist in repository.",
                )
        return explicit_base, head_sha

    # 2. Pull Request event
    if event_name == "pull_request":
        pr_base = (
            event_payload.get("pull_request", {})
            .get("base", {})
            .get("sha", "")
            .strip()
        )
        if pr_base:
            if not git_commit_exists(pr_base, repo_root):
                fetch_commit_if_needed(pr_base, repo_root)
            if git_commit_exists(pr_base, repo_root):
                return pr_base, head_sha
            raise BaseSHAResolutionError(
                attempted_method="pull_request.base.sha",
                head_sha=head_sha,
                candidate_shas=[pr_base],
                reason=f"PR base SHA '{pr_base}' could not be resolved in git history.",
            )
        raise BaseSHAResolutionError(
            attempted_method="pull_request event payload",
            head_sha=head_sha,
            candidate_shas=[],
            reason="Event payload missing pull_request.base.sha.",
        )

    # 3. Push event
    if event_name == "push":
        push_before = event_payload.get("before", "").strip()
        if (
            push_before
            and push_before != "0000000000000000000000000000000000000000"
        ):
            if not git_commit_exists(push_before, repo_root):
                fetch_commit_if_needed(push_before, repo_root)
            if git_commit_exists(push_before, repo_root):
                return push_before, head_sha

        # If push_before is 0000... (new branch creation), derive merge-base with origin/main
        candidate_shas: List[str] = []
        for ref_target in ["origin/main", "main", "HEAD~1"]:
            try:
                candidate = run_git(
                    ["merge-base", "HEAD", ref_target]
                    if "HEAD" not in ref_target
                    else ["rev-parse", ref_target],
                    cwd=repo_root,
                )
                if git_commit_exists(candidate, repo_root):
                    return candidate, head_sha
                candidate_shas.append(candidate)
            except Exception:
                pass

        raise BaseSHAResolutionError(
            attempted_method="push before SHA and merge-base fallback",
            head_sha=head_sha,
            candidate_shas=candidate_shas,
            reason="Push 'before' SHA was invalid or zero, and no parent or merge-base could be resolved.",
        )

    # 4. workflow_dispatch event (or local test run without compare_base_sha)
    candidates: List[str] = []

    # Candidate A: GitHub CLI / API for last completed run on same branch
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY")
    ref_name = os.environ.get("GITHUB_REF_NAME")
    if token and repo and ref_name:
        try:
            gh_cmd = [
                "gh",
                "run",
                "list",
                "--repo",
                repo,
                "--workflow",
                "build-ios26-unsigned-ipa.yml",
                "--branch",
                ref_name,
                "--status",
                "completed",
                "--limit",
                "5",
                "--json",
                "headSha,conclusion",
            ]
            res = subprocess.run(
                gh_cmd, capture_output=True, text=True, check=False
            )
            if res.returncode == 0:
                runs_data = json.loads(res.stdout)
                for run_entry in runs_data:
                    c_sha = run_entry.get("headSha", "")
                    if c_sha and c_sha != head_sha:
                        if git_commit_exists(c_sha, repo_root):
                            candidates.append(c_sha)
                            # Verify c_sha is an ancestor
                            is_ancestor = subprocess.run(
                                [
                                    "git",
                                    "merge-base",
                                    "--is-ancestor",
                                    c_sha,
                                    "HEAD",
                                ],
                                cwd=repo_root,
                                check=False,
                            ).returncode == 0
                            if is_ancestor:
                                return c_sha, head_sha
        except Exception:
            pass

    # Candidate B: merge-base with origin/main or origin/codex/*
    for target in [
        "origin/main",
        "main",
        "origin/codex/nativescript-swiftui-production",
        "codex/nativescript-swiftui-production",
    ]:
        try:
            mb = run_git(["merge-base", "HEAD", target], cwd=repo_root)
            if mb and git_commit_exists(mb, repo_root) and mb != head_sha:
                return mb, head_sha
        except Exception:
            pass

    # Candidate C: HEAD~1 (immediate parent)
    try:
        parent = run_git(["rev-parse", "HEAD~1"], cwd=repo_root)
        if parent and git_commit_exists(parent, repo_root):
            return parent, head_sha
    except Exception:
        pass

    raise BaseSHAResolutionError(
        attempted_method="workflow_dispatch candidate derivation",
        head_sha=head_sha,
        candidate_shas=candidates,
        reason=(
            "No explicit 'compare_base_sha' was supplied and could not establish "
            "a trustworthy ancestor base commit."
        ),
    )


def get_changed_files(
    repo_root: pathlib.Path, base_sha: str, head_sha: str
) -> List[str]:
    """Return list of modified/added/deleted files between base and head."""
    if base_sha == head_sha:
        return []

    diff_out = run_git(
        ["diff", "--name-only", base_sha, head_sha],
        cwd=repo_root,
    )
    files = [
        line.strip().replace("\\", "/")
        for line in diff_out.splitlines()
        if line.strip()
    ]
    return sorted(set(files))


class ValidationPlan:
    """Encapsulates the calculated CI plan and reasoning."""

    def __init__(
        self,
        base_sha: str,
        head_sha: str,
        event_name: str,
        changed_files: List[str],
        no_impact_files: List[str],
        affected_components: Dict[str, List[str]],
        selected_groups: Dict[str, List[str]],
        skipped_expensive_groups: Dict[str, str],
        step_outputs: Dict[str, Any],
        is_full_validation: bool,
        explicit_overrides: List[str],
    ) -> None:
        self.base_sha = base_sha
        self.head_sha = head_sha
        self.event_name = event_name
        self.changed_files = changed_files
        self.no_impact_files = no_impact_files
        self.affected_components = affected_components
        self.selected_groups = selected_groups
        self.skipped_expensive_groups = skipped_expensive_groups
        self.step_outputs = step_outputs
        self.is_full_validation = is_full_validation
        self.explicit_overrides = explicit_overrides

    def to_dict(self) -> Dict[str, Any]:
        return {
            "base_sha": self.base_sha,
            "head_sha": self.head_sha,
            "event_name": self.event_name,
            "is_full_validation": self.is_full_validation,
            "explicit_overrides": self.explicit_overrides,
            "changed_files_count": len(self.changed_files),
            "changed_files": self.changed_files,
            "no_impact_files": self.no_impact_files,
            "affected_components": self.affected_components,
            "selected_groups": self.selected_groups,
            "skipped_expensive_groups": self.skipped_expensive_groups,
            "step_outputs": self.step_outputs,
        }

    def render_markdown_summary(self) -> str:
        """Render a GitHub Actions step summary markdown document."""
        lines: List[str] = [
            "# Affected-Tests CI Validation Plan",
            "",
            "| Property | Value |",
            "| --- | --- |",
            f"| **Event** | `{self.event_name}` |",
            f"| **Base SHA** | `{self.base_sha[:10]}` (`{self.base_sha}`) |",
            f"| **Head SHA** | `{self.head_sha[:10]}` (`{self.head_sha}`) |",
            f"| **Changed Files** | `{len(self.changed_files)}` |",
            f"| **Full Validation Override** | `{str(self.is_full_validation).lower()}` |",
            f"| **Simulator UI Filter** | `{self.step_outputs.get('simulator_ui_filter') or 'None'}` |",
            f"| **Simulator Unit Filter** | `{self.step_outputs.get('simulator_unit_filter') or 'None'}` |",
            f"| **Simulator Configuration** | `{self.step_outputs.get('simulator_configuration', 'Debug')}` |",
            f"| **Simulator Build Args** | `{self.step_outputs.get('simulator_build_for_testing_args') or 'None'}` |",
            f"| **ScriptUI Fixture Staging** | `{str(self.step_outputs.get('stage_scriptui_fixtures', False)).lower()}` |",
        ]

        if self.explicit_overrides:
            overrides_str = ", ".join(f"`{o}`" for o in self.explicit_overrides)
            lines.append(f"| **Explicit Overrides** | {overrides_str} |")

        lines.append("")

        if self.is_full_validation:
            lines.append(
                "> [!WARNING]\n"
                "> **Full validation was explicitly enabled by the operator.**\n"
                "> All component suites, device build, and simulator acceptance tests are scheduled.\n"
            )

        # Changed files
        lines.append("### Changed Files")
        if not self.changed_files:
            lines.append("*No files changed in this comparison range.*")
        elif len(self.changed_files) <= 25:
            for f in self.changed_files:
                impact = " (no runtime impact)" if f in self.no_impact_files else ""
                lines.append(f"- `{f}`{impact}")
        else:
            for f in self.changed_files[:20]:
                impact = " (no runtime impact)" if f in self.no_impact_files else ""
                lines.append(f"- `{f}`{impact}")
            lines.append(f"- *...and {len(self.changed_files) - 20} more files*")
        lines.append("")

        # Affected components
        lines.append("### Affected Logical Components")
        if not self.affected_components:
            lines.append("*No logical runtime components affected.*")
        else:
            for comp, reasons in sorted(self.affected_components.items()):
                reasons_str = "; ".join(reasons[:2])
                lines.append(f"- **`{comp}`**: {reasons_str}")
        lines.append("")

        # Selected validation groups
        lines.append("### Selected Validation Groups")
        if not self.selected_groups:
            lines.append("*None -- all expensive validations safely skipped.*")
        else:
            for group, reasons in sorted(self.selected_groups.items()):
                lines.append(f"- **`{group}`**")
                for r in sorted(set(reasons)):
                    lines.append(f"  - *Reason*: {r}")
        lines.append("")

        # Skipped expensive groups
        lines.append("### Skipped Expensive Validations")
        if not self.skipped_expensive_groups:
            lines.append("*No expensive validations skipped (full validation active).*")
        else:
            for group_name, reason in sorted(
                self.skipped_expensive_groups.items()
            ):
                lines.append(f"- **{group_name}**: `SKIPPED` -- {reason}")
        lines.append("")

        return "\n".join(lines)


def plan_affected_validation(
    mapping_config: Dict[str, Any],
    changed_files: List[str],
    base_sha: str,
    head_sha: str,
    event_name: str,
    full_validation: bool = False,
    target_group: Optional[str] = None,
    manual_modes: Optional[Dict[str, bool]] = None,
) -> ValidationPlan:
    """Compute the affected validation plan from changed files and mapping rules."""
    manual_modes = manual_modes or {}
    no_impact_patterns: List[str] = mapping_config.get("no_impact_patterns", [])
    components: Dict[str, Any] = mapping_config.get("components", {})
    val_groups_config: Dict[str, Any] = mapping_config.get(
        "validation_groups", {}
    )
    expensive_items: List[Dict[str, str]] = mapping_config.get(
        "expensive_groups_for_summary", []
    )

    no_impact_files: List[str] = []
    file_to_components: Dict[str, List[str]] = collections.defaultdict(list)
    unmapped_files: List[str] = []

    # Map every changed file
    for file_path in changed_files:
        is_no_impact = any(
            match_pattern(file_path, pat) for pat in no_impact_patterns
        )
        if is_no_impact:
            no_impact_files.append(file_path)

        matched_components: List[str] = []
        for comp_name, comp_info in components.items():
            patterns: List[str] = comp_info.get("patterns", [])
            if any(match_pattern(file_path, pat) for pat in patterns):
                matched_components.append(comp_name)
                file_to_components[file_path].append(comp_name)

        if not is_no_impact and not matched_components:
            unmapped_files.append(file_path)

    # UNMAPPED FILES GUARD: Fail immediately if unknown files exist.
    # NEVER auto-run full validation as fallback.
    if unmapped_files:
        raise UnmappedPathsError(unmapped_files)

    explicit_overrides: List[str] = []
    selected_groups: Dict[str, List[str]] = collections.defaultdict(list)
    affected_components: Dict[str, List[str]] = collections.defaultdict(list)

    # If full_validation is explicitly requested:
    if full_validation:
        explicit_overrides.append("full_validation=true")
        for g_name, g_info in val_groups_config.items():
            selected_groups[g_name].append(
                "explicit operator request: full_validation=true"
            )
        for c_name in components:
            affected_components[c_name].append("full_validation active")

    # If manual modes were provided via workflow_dispatch:
    if manual_modes.get("runtime_bundle_only"):
        explicit_overrides.append("runtime_bundle_only=true")
        selected_groups["runtimecore_bundle"].append(
            "operator override: runtime_bundle_only=true"
        )

    if manual_modes.get("phase1_validation_only"):
        explicit_overrides.append("phase1_validation_only=true")
        for p1_group in [
            "ci_router",
            "scripting_reference",
            "scripting_compiler",
            "platform_contracts",
            "nativescript_runtime",
        ]:
            selected_groups[p1_group].append(
                "operator override: phase1_validation_only=true"
            )

    if manual_modes.get("fast_validation_only"):
        explicit_overrides.append("fast_validation_only=true")
        selected_groups["app_unit_tests"].append(
            "operator override: fast_validation_only=true"
        )
        selected_groups["simulator_smoke_launch"].append(
            "operator override: fast_validation_only=true"
        )

    if manual_modes.get("nativescript_poc_only"):
        explicit_overrides.append("nativescript_poc_only=true")
        selected_groups["nativescript_dependencies"].append(
            "operator override: nativescript_poc_only=true"
        )
        selected_groups["simulator_nativescript_poc"].append(
            "operator override: nativescript_poc_only=true"
        )

    if manual_modes.get("simulator_e2e_only"):
        explicit_overrides.append("simulator_e2e_only=true")
        selected_groups["simulator_targeted_ui"].append(
            "operator override: simulator_e2e_only=true"
        )

    if target_group and target_group.strip():
        tgt = target_group.strip()
        if tgt not in val_groups_config:
            valid_groups = ", ".join(sorted(val_groups_config.keys()))
            raise RoutingError(
                f"Unknown target validation group '{tgt}'. Valid groups: {valid_groups}"
            )
        explicit_overrides.append(f"target_validation_group={tgt}")
        selected_groups[tgt].append(
            f"explicit operator override: target_validation_group={tgt}"
        )

    # Perform normal dependency-aware routing from changed files
    # 1. Identify directly affected components
    for file_path, comps in file_to_components.items():
        for comp_name in comps:
            affected_components[comp_name].append(
                f"directly modified: {file_path}"
            )

    # 2. Expand transitive consumers
    queue = list(affected_components.keys())
    visited = set(queue)
    while queue:
        curr = queue.pop(0)
        curr_consumers = components.get(curr, {}).get("consumers", [])
        for consumer in curr_consumers:
            if consumer in components:
                affected_components[consumer].append(f"consumes {curr}")
                if consumer not in visited:
                    visited.add(consumer)
                    queue.append(consumer)
            elif consumer in val_groups_config:
                selected_groups[consumer].append(f"consumes component '{curr}'")

    # 3. Map affected components to direct validation groups
    for comp_name, reasons in affected_components.items():
        if comp_name not in components:
            continue
        c_groups = components[comp_name].get("direct_validation_groups", [])
        for g in c_groups:
            if g in val_groups_config:
                selected_groups[g].append(
                    f"component '{comp_name}' was affected ({reasons[0]})"
                )

    # 3b. Resolve component-level prerequisites
    for comp_name in list(affected_components.keys()):
        c_prereqs = components.get(comp_name, {}).get("prerequisites", [])
        for p in c_prereqs:
            if p in val_groups_config and p not in selected_groups:
                selected_groups[p].append(f"prerequisite for component '{comp_name}'")

    # 4. Resolve prerequisites of selected validation groups
    prereq_queue = list(selected_groups.keys())
    while prereq_queue:
        curr_g = prereq_queue.pop(0)
        prereqs = val_groups_config.get(curr_g, {}).get("prerequisites", [])
        for p in prereqs:
            if p not in selected_groups:
                selected_groups[p].append(f"prerequisite for '{curr_g}'")
                prereq_queue.append(p)

    # Apply operator overrides that suppress specific validation stages
    if manual_modes.get("simulator_e2e_only") and not full_validation:
        if target_group not in ("device_build", "ipa_packaging"):
            selected_groups.pop("device_build", None)
            selected_groups.pop("ipa_packaging", None)
        if target_group != "app_unit_tests":
            selected_groups.pop("app_unit_tests", None)
        if target_group != "simulator_scripting_acceptance":
            selected_groups.pop("simulator_scripting_acceptance", None)

    # Derive targeted UI suites
    affected_ui_suites: Set[str] = set()
    for comp_name in affected_components:
        comp_info = components.get(comp_name, {})
        for suite in comp_info.get("ui_suites", []):
            affected_ui_suites.add(suite)

    if full_validation:
        for comp_info in components.values():
            for suite in comp_info.get("ui_suites", []):
                affected_ui_suites.add(suite)
    elif target_group == "simulator_targeted_ui" and not affected_ui_suites:
        for comp_info in components.values():
            for suite in comp_info.get("ui_suites", []):
                affected_ui_suites.add(suite)
    elif manual_modes.get("simulator_e2e_only") and not affected_ui_suites and not file_to_components:
        for comp_info in components.values():
            for suite in comp_info.get("ui_suites", []):
                affected_ui_suites.add(suite)

    if "simulator_targeted_ui" in selected_groups and not full_validation:
        if not affected_ui_suites:
            raise RoutingError(
                "Targeted UI validation ('simulator_targeted_ui') was selected, "
                "but no specific UI test suite mapping was found for the affected components: "
                f"{sorted(affected_components.keys())}. "
                "Define 'ui_suites' for the affected component in Scripts/CI/affected-validation-map.json "
                "or run with explicit full_validation."
            )

    # If a parent suite is selected (e.g. AI_HLYUITests/HanlinRuntimeInstallationUITests),
    # prune child method-level selectors (e.g. .../testMethod) to prevent xcodebuild from running them twice.
    pruned_ui_suites: Set[str] = set()
    for suite in affected_ui_suites:
        if any(other != suite and suite.startswith(other + "/") for other in affected_ui_suites):
            continue
        pruned_ui_suites.add(suite)
    affected_ui_suites = pruned_ui_suites

    simulator_ui_filter_value = ",".join(sorted(affected_ui_suites))
    requires_scriptui_fixtures = (
        full_validation
        or ("AI_HLYUITests/HanlinScriptUIProductionE2ETests" in affected_ui_suites)
        or ("HanlinScriptUIProductionE2ETests" in simulator_ui_filter_value)
    )

    # Derive targeted unit suites
    affected_unit_suites: Set[str] = set()
    if not full_validation:
        for comp_name in affected_components:
            comp_info = components.get(comp_name, {})
            for suite in comp_info.get("unit_suites", []):
                affected_unit_suites.add(suite)
    else:
        affected_unit_suites = {"AI_HLYTests"}

    if (target_group == "app_unit_tests" or manual_modes.get("fast_validation_only")) and not affected_unit_suites and not full_validation:
        for comp_info in components.values():
            for suite in comp_info.get("unit_suites", []):
                affected_unit_suites.add(suite)

    if "app_unit_tests" in selected_groups and not full_validation:
        if not affected_unit_suites:
            raise RoutingError(
                "Targeted unit test validation ('app_unit_tests') was selected, "
                "but no specific unit test suite mapping was found for the affected components: "
                f"{sorted(affected_components.keys())}. "
                "Define 'unit_suites' for the affected component in Scripts/CI/affected-validation-map.json "
                "or run with explicit full_validation."
            )

    # If a parent suite is selected (e.g. AI_HLYTests), prune child selectors
    pruned_unit_suites: Set[str] = set()
    for suite in affected_unit_suites:
        if any(other != suite and suite.startswith(other + "/") for other in affected_unit_suites):
            continue
        pruned_unit_suites.add(suite)
    affected_unit_suites = pruned_unit_suites

    NODE_DEPENDENT_UNIT_SUITES = {
        "AI_HLYTests/HanlinScriptPackageProductionE2ETests",
        "AI_HLYTests/HanlinScriptingProductionCompilerAcceptanceTests",
        "AI_HLYTests/HanlinScriptPackagePhysicalIPadRegressionTests",
        "AI_HLYTests/HanlinTrustedWorkerRouteTests",
    }
    if any(
        s in NODE_DEPENDENT_UNIT_SUITES
        or any(s.startswith(nd + "/") for nd in NODE_DEPENDENT_UNIT_SUITES)
        for s in affected_unit_suites
    ):
        if "runtimecore_host" not in selected_groups:
            selected_groups["runtimecore_host"].append(
                "selected unit suite requires Node runtime host"
            )

    if full_validation:
        simulator_unit_filter_value = "AI_HLYTests"
    elif affected_unit_suites:
        simulator_unit_filter_value = ",".join(sorted(affected_unit_suites))
    else:
        simulator_unit_filter_value = ""

    # 5. Formulate step outputs
    step_outputs: Dict[str, Any] = {
        "run_full_validation": full_validation,
        "run_phase1": False,
        "run_ci_router": False,
        "run_scripting_reference": False,
        "run_scripting_compiler": False,
        "run_platform_contracts": False,
        "run_nativescript_dependencies": False,
        "run_nativescript_runtime": False,
        "run_runtimecore_bundle": False,
        "run_runtimecore_host": False,
        "run_device_build": False,
        "run_ipa_packaging": False,
        "run_simulator_job": False,
        "run_simulator_unit": False,
        "simulator_unit_filter": simulator_unit_filter_value,
        "run_simulator_scripting_acceptance": False,
        "run_simulator_targeted_ui": False,
        "simulator_ui_filter": simulator_ui_filter_value,
        "stage_scriptui_fixtures": bool(requires_scriptui_fixtures),
        "run_simulator_shell_acceptance": False,
        "run_simulator_mcp_acceptance": False,
        "run_simulator_smoke_launch": False,
        "run_simulator_nativescript_poc": False,
        "selected_groups": ",".join(sorted(selected_groups.keys())),
        "base_sha": base_sha,
        "head_sha": head_sha,
        "changed_files_count": len(changed_files),
    }

    # Apply workflow outputs from selected groups
    for g_name in selected_groups:
        g_info = val_groups_config.get(g_name, {})
        g_outputs = g_info.get("workflow_outputs", {})
        for out_k, out_v in g_outputs.items():
            if out_k == "simulator_unit_filter" and not full_validation and affected_unit_suites:
                continue
            step_outputs[out_k] = out_v

    # Enforce simulator_e2e_only strict suppression on step outputs
    if manual_modes.get("simulator_e2e_only") and not full_validation:
        if target_group not in ("device_build", "ipa_packaging"):
            step_outputs["run_device_build"] = False
            step_outputs["run_ipa_packaging"] = False
        if target_group != "app_unit_tests":
            step_outputs["run_simulator_unit"] = False
        if target_group != "simulator_scripting_acceptance":
            step_outputs["run_simulator_scripting_acceptance"] = False

    # Ensure composite job flags are set correctly
    if any(
        step_outputs.get(k)
        for k in [
            "run_ci_router",
            "run_scripting_reference",
            "run_scripting_compiler",
            "run_platform_contracts",
            "run_nativescript_runtime",
        ]
    ):
        step_outputs["run_phase1"] = True

    if any(
        step_outputs.get(k)
        for k in [
            "run_simulator_unit",
            "run_simulator_scripting_acceptance",
            "run_simulator_targeted_ui",
            "run_simulator_shell_acceptance",
            "run_simulator_mcp_acceptance",
            "run_simulator_smoke_launch",
            "run_simulator_nativescript_poc",
        ]
    ):
        step_outputs["run_simulator_job"] = True

    # 6. Determine simulator configuration (Debug vs Release)
    # Routine targeted functional UI acceptance and unit tests use Debug.
    # Release is used when full validation is enabled, or when the affected
    # components/groups specifically require linker/runtime/native/production validation.
    release_triggers = {
        "nativescript_runtime",
        "nativescript_dependencies",
        "nativescript_fixtures",
        "nativescript_ui_test_files",
        "simulator_nativescript_poc",
        "runtimecore_bundle",
        "runtime_tools",
        "project_packaging",
        "python_runtime",
        "node_runtime",
        "ios_system",
        "simulator_shell_acceptance",
        "simulator_mcp_acceptance",
        "device_build",
        "ipa_packaging",
    }
    if full_validation:
        simulator_configuration = "Release"
    elif any(g in selected_groups for g in release_triggers):
        simulator_configuration = "Release"
    elif any(c in affected_components for c in release_triggers):
        simulator_configuration = "Release"
    else:
        simulator_configuration = "Debug"

    # 7. Formulate scoped build-for-testing arguments
    build_for_testing_args: List[str] = []
    if full_validation:
        build_for_testing_args = ["-only-testing:AI_HLYTests", "-only-testing:AI_HLYUITests"]
    else:
        if step_outputs.get("run_simulator_unit"):
            unit_filter = step_outputs.get("simulator_unit_filter", "")
            for u in unit_filter.split(","):
                u = u.strip()
                if u:
                    build_for_testing_args.append(f"-only-testing:{u}")
        if step_outputs.get("run_simulator_scripting_acceptance"):
            build_for_testing_args.append("-only-testing:AI_HLYTests/HanlinScriptingAcceptanceTests")
        if step_outputs.get("run_simulator_targeted_ui"):
            ui_filter = step_outputs.get("simulator_ui_filter", "")
            for s in ui_filter.split(","):
                s = s.strip()
                if s:
                    build_for_testing_args.append(f"-only-testing:{s}")

    simulator_build_for_testing_args_value = " ".join(build_for_testing_args)

    step_outputs["simulator_configuration"] = simulator_configuration
    step_outputs["simulator_build_for_testing_args"] = simulator_build_for_testing_args_value

    # 8. Determine skipped expensive groups for clear reporting
    skipped_expensive: Dict[str, str] = {}
    for item in expensive_items:
        exp_name = item["name"]
        exp_group = item["validation_group"]
        if exp_group not in selected_groups:
            if manual_modes.get("simulator_e2e_only") and exp_group in (
                "device_build",
                "ipa_packaging",
                "app_unit_tests",
                "simulator_scripting_acceptance",
            ):
                skipped_expensive[exp_name] = "suppressed by simulator_e2e_only operator override"
            else:
                skipped_expensive[exp_name] = "not affected by changed files"

    return ValidationPlan(
        base_sha=base_sha,
        head_sha=head_sha,
        event_name=event_name,
        changed_files=changed_files,
        no_impact_files=no_impact_files,
        affected_components=dict(affected_components),
        selected_groups=dict(selected_groups),
        skipped_expensive_groups=skipped_expensive,
        step_outputs=step_outputs,
        is_full_validation=full_validation,
        explicit_overrides=explicit_overrides,
    )


def write_github_output(outputs: Dict[str, Any], output_path: str) -> None:
    """Write outputs to GitHub Actions output environment file."""
    with open(output_path, "a", encoding="utf-8") as f:
        for k, v in outputs.items():
            if isinstance(v, bool):
                str_val = "true" if v else "false"
            else:
                str_val = str(v)
            f.write(f"{k}={str_val}\n")


def write_step_summary(summary_md: str, summary_path: str) -> None:
    """Write markdown summary to GITHUB_STEP_SUMMARY."""
    with open(summary_path, "a", encoding="utf-8") as f:
        f.write(summary_md + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Plan affected CI validations based on git diff and dependency graph."
    )
    parser.add_argument(
        "--repository",
        default=".",
        help="Path to repository root (default: current directory)",
    )
    parser.add_argument(
        "--map",
        default="Scripts/CI/affected-validation-map.json",
        help="Path to affected-validation-map.json",
    )
    parser.add_argument(
        "--event-name",
        default=os.environ.get("GITHUB_EVENT_NAME", "workflow_dispatch"),
        help="GitHub event name (workflow_dispatch, push, pull_request)",
    )
    parser.add_argument(
        "--event-path",
        default=os.environ.get("GITHUB_EVENT_PATH"),
        help="Path to GitHub event JSON file",
    )
    parser.add_argument(
        "--base-sha",
        help="Explicit base commit SHA (or compare_base_sha input)",
    )
    parser.add_argument(
        "--head-sha",
        help="Explicit head commit SHA (defaults to HEAD)",
    )
    parser.add_argument(
        "--full-validation",
        action="store_true",
        default=False,
        help="Explicit operator request to run the complete validation suite across all components (DEFAULT: false)",
    )
    parser.add_argument(
        "--target-group",
        help="Explicitly run a targeted validation group (e.g. nativescript_runtime, simulator_targeted_ui)",
    )
    parser.add_argument(
        "--runtime-bundle-only",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--phase1-validation-only",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--fast-validation-only",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--nativescript-poc-only",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--simulator-e2e-only",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--json-output",
        help="Path to write the resulting plan JSON",
    )
    parser.add_argument(
        "--github-output",
        default=os.environ.get("GITHUB_OUTPUT"),
        help="Path to GITHUB_OUTPUT file",
    )
    parser.add_argument(
        "--github-step-summary",
        default=os.environ.get("GITHUB_STEP_SUMMARY"),
        help="Path to GITHUB_STEP_SUMMARY file",
    )

    args = parser.parse_args()
    repo_root = pathlib.Path(args.repository).resolve()

    map_path = (
        pathlib.Path(args.map)
        if pathlib.Path(args.map).is_absolute()
        else repo_root / args.map
    )
    if not map_path.exists():
        sys.stderr.write(f"Routing map file not found: {map_path}\n")
        return 1

    with open(map_path, "r", encoding="utf-8") as f:
        mapping_config = json.load(f)

    event_payload: Dict[str, Any] = {}
    if args.event_path and pathlib.Path(args.event_path).exists():
        try:
            with open(args.event_path, "r", encoding="utf-8") as f:
                event_payload = json.load(f)
        except Exception as e:
            sys.stderr.write(
                f"Warning: could not parse event payload from {args.event_path}: {e}\n"
            )

    manual_modes = {
        "runtime_bundle_only": args.runtime_bundle_only,
        "phase1_validation_only": args.phase1_validation_only,
        "fast_validation_only": args.fast_validation_only,
        "nativescript_poc_only": args.nativescript_poc_only,
        "simulator_e2e_only": args.simulator_e2e_only,
    }

    try:
        base_sha, head_sha = resolve_comparison_range(
            repo_root=repo_root,
            event_name=args.event_name,
            event_payload=event_payload,
            compare_base_sha_input=args.base_sha,
            head_sha_input=args.head_sha,
        )
        changed_files = get_changed_files(
            repo_root=repo_root, base_sha=base_sha, head_sha=head_sha
        )
        plan = plan_affected_validation(
            mapping_config=mapping_config,
            changed_files=changed_files,
            base_sha=base_sha,
            head_sha=head_sha,
            event_name=args.event_name,
            full_validation=args.full_validation,
            target_group=args.target_group,
            manual_modes=manual_modes,
        )
    except UnmappedPathsError as err:
        err_msg = [
            "================================================================================",
            "ROUTING ERROR: Affected-test routing is incomplete.",
            "",
            "Unmapped changed paths:",
        ]
        for p in err.unmapped_paths:
            err_msg.append(f"  - {p}")
        err_msg.extend(
            [
                "",
                "Add an explicit routing rule in Scripts/CI/affected-validation-map.json before validation can continue.",
                "DO NOT RUN FULL VALIDATION AS A FALLBACK.",
                "================================================================================",
            ]
        )
        full_text = "\n".join(err_msg)
        sys.stderr.write(full_text + "\n")
        if args.github_step_summary:
            summary_err = (
                f"## ❌ Affected-Tests CI Routing Incomplete\n\n"
                f"The following changed paths have no routing rule:\n\n"
                + "\n".join(f"- `{p}`" for p in err.unmapped_paths)
                + "\n\n**Action required**: Add an explicit routing rule or classify as `no_impact` in `Scripts/CI/affected-validation-map.json`.\n"
                + "\n*Full validation will never run automatically as a fallback.*\n"
            )
            write_step_summary(summary_err, args.github_step_summary)
        return 1

    except BaseSHAResolutionError as err:
        err_msg = [
            "================================================================================",
            "ROUTING ERROR: Could not establish a reliable comparison base SHA.",
            f"Attempted comparison method: {err.attempted_method}",
            f"Head SHA: {err.head_sha}",
            f"Available candidate base SHA(s): {', '.join(err.candidate_shas) or 'None'}",
            f"Why a trustworthy diff could not be established: {err.reason}",
            "",
            "Action required: Provide an explicit 'compare_base_sha' input to workflow_dispatch.",
            "DO NOT RUN FULL VALIDATION AS A FALLBACK.",
            "================================================================================",
        ]
        full_text = "\n".join(err_msg)
        sys.stderr.write(full_text + "\n")
        if args.github_step_summary:
            summary_err = (
                f"## ❌ Comparison Base SHA Resolution Failed\n\n"
                f"- **Attempted method**: `{err.attempted_method}`\n"
                f"- **Head SHA**: `{err.head_sha}`\n"
                f"- **Candidates**: `{', '.join(err.candidate_shas) or 'None'}`\n"
                f"- **Reason**: {err.reason}\n\n"
                f"**Action required**: Supply an explicit `compare_base_sha` input.\n"
                f"*Full validation will never run automatically as a fallback.*\n"
            )
            write_step_summary(summary_err, args.github_step_summary)
        return 1

    except RoutingError as err:
        sys.stderr.write(f"ROUTING ERROR: {err}\n")
        return 1

    # Render summary and outputs
    summary_md = plan.render_markdown_summary()
    print(summary_md)

    if args.json_output:
        with open(args.json_output, "w", encoding="utf-8") as f:
            json.dump(plan.to_dict(), f, indent=2)

    if args.github_output:
        write_github_output(plan.step_outputs, args.github_output)

    if args.github_step_summary:
        write_step_summary(summary_md, args.github_step_summary)

    return 0


if __name__ == "__main__":
    sys.exit(main())
