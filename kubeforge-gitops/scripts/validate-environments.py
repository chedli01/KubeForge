#!/usr/bin/env python3
"""Validate every Argo CD-managed DevEnvironment against the Crossplane XRD.

Runs locally and in GitHub Actions; never contacts a Kubernetes cluster.
"""

import argparse
import copy
import re
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

# The XR name is reused as the Namespace name in our Composition.
NAMESPACE_NAME = re.compile(r"^[a-z0-9](?:[-a-z0-9]*[a-z0-9])?$")
RESERVED_NAMESPACES = {
    "default",
    "kube-system",
    "kube-public",
    "kube-node-lease",
    "argocd",
    "crossplane-system",
}


class UniqueKeyLoader(yaml.SafeLoader):
    """Reject duplicate mapping keys that YAML parsers ordinarily overwrite."""


def construct_unique_mapping(loader, node):
    loader.flatten_mapping(node)
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=True)
        if not isinstance(key, str):
            raise ValueError("YAML mapping keys must be strings")
        if key in mapping:
            raise ValueError(f"duplicate YAML key: {key!r}")
        mapping[key] = loader.construct_object(value_node, deep=True)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_unique_mapping
)


def error(path: Path, message: str):
    """Print a readable error and annotate GitHub pull requests."""
    print(f"ERROR {path}: {message}", file=sys.stderr)
    # Escape GitHub workflow-command special characters, including newlines.
    safe_file = str(path).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A").replace(",", "%2C")
    safe_msg = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error file={safe_file}::{safe_msg}")


def read_single_yaml(path: Path):
    with path.open("r", encoding="utf-8") as stream:
        documents = list(yaml.load_all(stream, Loader=UniqueKeyLoader))
    if len(documents) != 1 or documents[0] is None:
        raise ValueError("expected exactly one non-empty YAML document per file")
    if not isinstance(documents[0], dict):
        raise ValueError("YAML document must be an object (mapping)")
    return documents[0]


def read_xrd(path: Path):
    xrd = read_single_yaml(path)
    if xrd.get("kind") != "CompositeResourceDefinition":
        raise ValueError("expected a Crossplane CompositeResourceDefinition")
    definition = xrd.get("spec", {})
    if definition.get("scope") != "Cluster":
        raise ValueError("KubeForge expects a cluster-scoped DevEnvironment XR")

    versions = [
        v for v in definition.get("versions", [])
        if v.get("served") and v.get("referenceable")
    ]
    if len(versions) != 1:
        raise ValueError("expected exactly one served, referenceable XRD version")

    version = versions[0]
    schema = copy.deepcopy(version["schema"]["openAPIV3Schema"])
    if "spec" not in schema.get("properties", {}):
        raise ValueError("XRD schema does not define spec")

    # Kubernetes may silently prune unknown spec keys. Fail the PR instead.
    schema["properties"]["spec"]["additionalProperties"] = False
    Draft202012Validator.check_schema(schema)
    return (
        f"{definition['group']}/{version['name']}",
        definition["names"]["kind"],
        Draft202012Validator(schema),
    )


def validate_request(path: Path, doc: dict, api_version: str, kind: str, validator):
    issues = []
    if doc.get("apiVersion") != api_version:
        issues.append(f"apiVersion must be {api_version!r}")
    if doc.get("kind") != kind:
        issues.append(f"kind must be {kind!r}")

    unexpected_top = set(doc) - {"apiVersion", "kind", "metadata", "spec"}
    if unexpected_top:
        issues.append(f"unexpected top-level field(s): {', '.join(sorted(unexpected_top))}")

    metadata = doc.get("metadata")
    if not isinstance(metadata, dict):
        issues.append("metadata must be an object with a name")
        name = None
    else:
        # Developers only need the XR name. Disallow managed fields, namespace,
        # finalizers, annotations, etc. in GitOps self-service requests.
        extra_metadata = set(metadata) - {"name"}
        if extra_metadata:
            issues.append(f"unsupported metadata field(s): {', '.join(sorted(extra_metadata))}")
        name = metadata.get("name")
        if not isinstance(name, str) or not (1 <= len(name) <= 63) or not NAMESPACE_NAME.fullmatch(name):
            issues.append("metadata.name must be a lowercase DNS label (1-63 characters; a-z, 0-9, '-')")
        elif name.startswith("kube-") or name in RESERVED_NAMESPACES:
            issues.append(f"metadata.name {name!r} is reserved for cluster/platform namespaces")

    for problem in sorted(validator.iter_errors(doc), key=lambda item: (list(map(str, item.absolute_path)), item.message)):
        location = ".".join(map(str, problem.absolute_path)) or "root"
        issues.append(f"{location}: {problem.message}")

    return name, issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xrd", type=Path, required=True, help="Path to the real DevEnvironment XRD")
    parser.add_argument("--environments", type=Path, required=True, help="Argo CD watched environments directory")
    args = parser.parse_args()

    if not args.xrd.is_file():
        error(args.xrd, "XRD file does not exist")
        return 1
    if not args.environments.is_dir():
        error(args.environments, "environments directory does not exist")
        return 1

    try:
        api_version, kind, validator = read_xrd(args.xrd)
    except (OSError, yaml.YAMLError, ValueError, KeyError, TypeError) as exc:
        error(args.xrd, f"invalid XRD/schema: {exc}")
        return 1

    print(f"Validating {kind} requests against {api_version} from {args.xrd}")
    errors = 0
    valid = 0
    seen_names = {}

    # Argo CD is configured with directory.recurse=false and include="*.yaml".
    # Catch requests that would otherwise be silently ignored by Argo CD.
    for path in sorted(args.environments.rglob("*")):
        if path.is_symlink():
            error(path, "symbolic links are not accepted in the environments directory")
            errors += 1
            continue
        if not path.is_file():
            continue
        if path.suffix == ".yml":
            error(path, "use .yaml; Argo CD is configured to include only *.yaml")
            errors += 1
            continue
        if path.suffix != ".yaml":
            continue
        if path.parent != args.environments:
            error(path, "move the request to the environments directory root; Argo CD recursion is disabled")
            errors += 1
            continue

        try:
            doc = read_single_yaml(path)
            name, issues = validate_request(path, doc, api_version, kind, validator)
        except (OSError, yaml.YAMLError, ValueError, TypeError) as exc:
            name, issues = None, [f"invalid YAML: {exc}"]

        if isinstance(name, str) and name in seen_names:
            issues.append(f"duplicate DevEnvironment name {name!r}; also declared in {seen_names[name]}")
        elif isinstance(name, str):
            seen_names[name] = path

        if issues:
            for issue in issues:
                error(path, issue)
                errors += 1
        else:
            valid += 1
            print(f"PASS {path}: {name}")

    if errors:
        print(f"FAILED: {errors} validation error(s) in environment requests", file=sys.stderr)
        return 1
    print(f"SUCCESS: {valid} valid DevEnvironment request(s). No cluster access required.")
    if not valid:
        print("Note: zero requests is allowed; Argo CD may prune managed XRs when the directory is empty.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
