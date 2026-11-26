#!/usr/bin/env python3
"""Require every source-declared cache app test invocation to pass.

This deliberately bounded Swift declaration reader accepts the selected suites'
current zero-argument methods and finite inline String argument arrays. Comments,
ordinary/raw/multiline strings, and string interpolation are lexed before looking
for attributes. New declaration/argument shapes block until reviewed. Actual
xcresult matching reuses the original strict native-tool candidate verifier,
including complete argument displays and unique ?args= identities.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

from verify_native_tool_candidate import inspect_result, signature
from xcresult_to_xunit import nodes

SUITES = ("HanlinPromptCachingIntegrationTests", "ClassicChatRestorationTests",
          "HanlinMiniAppAssistantIntegrationTests", "HanlinModelPromptCachePersistenceTests")


def swift_tokens(source):
    """Return (kind, spelling, offset), excluding comments and string contents."""
    def token_at(offset):
        while offset < len(source):
            if source[offset].isspace():
                offset += 1
            elif source.startswith("//", offset):
                end = source.find("\n", offset)
                offset = len(source) if end < 0 else end + 1
            elif source.startswith("/*", offset):
                depth, offset = 1, offset + 2
                while depth and offset < len(source):
                    if source.startswith("/*", offset):
                        depth, offset = depth + 1, offset + 2
                    elif source.startswith("*/", offset):
                        depth, offset = depth - 1, offset + 2
                    else:
                        offset += 1
                if depth:
                    raise ValueError("Unterminated Swift block comment")
            else:
                break
        if offset == len(source):
            return None, offset
        start = offset
        opening = re.match(r'(#{0,})("""|")', source[offset:])
        if opening:
            hashes, quotes = opening.groups()
            offset += len(opening[0])
            closing, escape = quotes + hashes, "\\" + hashes
            while offset < len(source):
                if source.startswith(closing, offset):
                    end = offset + len(closing)
                    return ("string", source[start:end], start), end
                if source.startswith(escape, offset):
                    offset += len(escape)
                    if source.startswith("(", offset):
                        depth, offset = 1, offset + 1
                        while depth:
                            token, offset = token_at(offset)
                            if token is None:
                                raise ValueError("Unterminated Swift interpolation")
                            if token[1] == "(":
                                depth += 1
                            elif token[1] == ")":
                                depth -= 1
                    else:
                        offset += 1
                else:
                    offset += 1
            raise ValueError("Unterminated Swift string")
        identifier = re.match(r"[A-Za-z_][A-Za-z_0-9]*", source[offset:])
        if identifier:
            end = offset + len(identifier[0])
            return ("identifier", identifier[0], start), end
        return ("punctuation", source[offset], start), offset + 1

    result, offset = [], 0
    while offset < len(source):
        token, offset = token_at(offset)
        if token is not None:
            result.append(token)
    return result


def closing_index(tokens, start):
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = []
    for index in range(start, len(tokens)):
        value = tokens[index][1]
        if tokens[index][0] == "string":
            continue
        if value in pairs:
            stack.append(pairs[value])
        elif value in pairs.values():
            if not stack or stack.pop() != value:
                raise ValueError("Unbalanced Swift declaration")
            if not stack:
                return index
    raise ValueError("Unclosed Swift declaration")


def literal_string(token):
    kind, text, _ = token
    if kind != "string":
        raise ValueError("Only finite inline String argument literals are supported")
    opening = re.match(r'(#{0,})("""|")', text)
    hashes, quotes = opening.groups()
    if quotes != '"':
        raise ValueError("Multiline test argument literals require explicit review")
    body = text[len(opening[0]):-len(quotes + hashes)]
    if hashes:
        if "\\" + hashes in body:
            raise ValueError("Interpolated/escaped raw test arguments require explicit review")
        return body
    # JSON's string subset has unambiguous matching Swift semantics. Unsupported
    # Swift-only escapes/interpolation block instead of guessing actual values.
    return json.loads(text)


def parse_suite(source, suite):
    tokens = swift_tokens(source)
    values = [token[1] for token in tokens]
    starts = [index for index in range(len(tokens) - 2)
              if values[index:index + 3] == ["struct", suite, "{"]]
    if len(starts) != 1:
        raise ValueError("Expected one exact selected suite struct: " + suite)
    start = starts[0] + 2
    end = closing_index(tokens, start)
    tests = [index for index in range(len(tokens) - 1)
             if values[index:index + 2] == ["@", "Test"]]
    methods, declarations = {}, []
    for index in tests:
        if not start < index < end:
            raise ValueError("Test declared outside selected suite: " + suite)
        depth = sum(1 if token[1] == "{" else -1 if token[1] == "}" else 0
                    for token in tokens[start:index] if token[0] != "string")
        if depth != 1:
            raise ValueError("Nested test declarations require explicit review")
        cursor, attributes = index + 2, []
        if values[cursor] == "(":
            close = closing_index(tokens, cursor)
            attributes, cursor = tokens[cursor + 1:close], close + 1
        while values[cursor:cursor + 2] == ["@", "MainActor"]:
            cursor += 2
        if values[cursor] != "func" or tokens[cursor + 1][0] != "identifier":
            raise ValueError("Unsupported @Test declaration in " + suite)
        method, parameters = values[cursor + 1], cursor + 2
        if values[parameters] != "(":
            raise ValueError("Unsupported generic test: " + method)
        close = closing_index(tokens, parameters)
        parameter_values = values[parameters + 1:close]
        argument_labels = [i for i in range(len(attributes) - 1)
                           if attributes[i][0] != "string"
                           and [row[1] for row in attributes[i:i + 2]] == ["arguments", ":"]]
        arguments = None
        if argument_labels:
            if len(argument_labels) != 1 or len(parameter_values) != 4 or (
                    parameter_values[0] != "_" or parameter_values[2:] != [":", "String"]):
                raise ValueError("Unsupported parameterized declaration: " + method)
            first = argument_labels[0] + 2
            if first >= len(attributes) or attributes[first][1] != "[":
                raise ValueError("Test arguments must be a finite inline array: " + method)
            last = closing_index(attributes, first)
            if last != len(attributes) - 1:
                raise ValueError("Unexpected fields following test argument array")
            rows = attributes[first + 1:last]
            if rows and rows[-1][1] == ",":
                rows = rows[:-1]
            if not rows or any(row[1] != "," for row in rows[1::2]):
                raise ValueError("Unsupported test argument expression: " + method)
            arguments = [(literal_string(row),) for row in rows[::2]]
            if len(set(arguments)) != len(arguments):
                raise ValueError("Duplicate source test arguments: " + method)
        elif parameter_values:
            raise ValueError("Parameterized test is missing an exact argument inventory: " + method)
        if method in methods:
            raise ValueError("Duplicate or overloaded test declaration: " + method)
        methods[method] = arguments
        declarations.append({"id": signature(suite + "/" + method, arguments),
                             "line": source.count("\n", 0, tokens[index][2]) + 1,
                             "arguments": arguments})
    if not methods:
        raise ValueError("Selected suite declares no supported tests: " + suite)
    return methods, declarations


def source_inventory(repository):
    suites, files, declarations = {}, {}, []
    for suite in SUITES:
        relative = "AI_HLYTests/" + suite + ".swift"
        raw = (repository / relative).read_bytes()
        methods, records = parse_suite(raw.decode("utf-8"), suite)
        suites[suite] = methods
        files[relative] = hashlib.sha256(raw).hexdigest()
        declarations.extend(dict(record, source=relative) for record in records)
    return {
        "suites": suites, "sourceFiles": files, "declarations": declarations,
        "expectedMethodCount": len(declarations),
        "expectedInvocationCount": sum(1 if args is None else len(args)
                                      for methods in suites.values() for args in methods.values()),
    }


def verify_results(result_file, inventory):
    # Do not substitute aggregate method PASS for any parameterized invocation.
    cases, methods, errors = inspect_result(result_file.parent, result_file.stem, inventory["suites"])
    data = json.loads(result_file.read_text())
    actual_nodes = list(nodes(data))
    for node in actual_nodes:
        if node.get("nodeType") != "Test Case":
            continue
        identifier, url = node.get("nodeIdentifier", ""), node.get("nodeIdentifierURL", "")
        if not isinstance(url, str) or not unquote(urlsplit(url).path).endswith(
                "/AI_HLYTests/" + identifier):
            errors.append("Selected method is not identified in the original AI_HLYTests target: " + str(identifier))
    observed = [case for case in cases if case.get("node_identifier_url")]
    passed = [case for case in observed if case["status"] == "PASS"]
    ok = (not errors and len(methods) == inventory["expectedMethodCount"]
          and len(passed) == len(cases) == inventory["expectedInvocationCount"])
    return {
        "status": "PASS" if ok else "BLOCKED",
        "resultSHA256": hashlib.sha256(result_file.read_bytes()).hexdigest(),
        "expectedMethodCount": inventory["expectedMethodCount"],
        "expectedInvocationCount": inventory["expectedInvocationCount"],
        "observedInvocationCount": len(observed), "passedInvocationCount": len(passed),
        "cases": cases, "methods": methods, "errors": sorted(errors),
        "nonPassingResultNodes": [
            {"nodeType": node.get("nodeType"), "identifier": node.get("nodeIdentifierURL"),
             "result": node.get("result")}
            for node in actual_nodes if node.get("nodeType") in {"Test Case", "Arguments"}
            and node.get("result") != "Passed"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True, type=Path)
    parser.add_argument("--results", required=True, type=Path)
    args = parser.parse_args()
    report = verify_results(args.results, json.loads(args.inventory.read_text()))
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
