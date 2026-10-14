"""Regression tests for the GitOps request validator (no Kubernetes needed)."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "kubeforge-gitops" / "scripts" / "validate-environments.py"
# From the project root (KubeForge/):
XRD = REPO / "kubeforge-platform" / "manifests" / "xrds" / "dev-environment.yaml"

VALID = """\
apiVersion: platform.kubeforge.io/v1alpha1
kind: DevEnvironment
metadata:
  name: ci-test
spec:
  team: payments
  size: small
"""


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name)
        self.envs = self.folder / "environments"
        self.envs.mkdir()

    def run_validator(self, *files, expected_success=True):
        for name, content in files:
            path = self.envs / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--xrd", str(XRD), "--environments", str(self.envs)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(proc.returncode == 0, expected_success, proc.stdout)
        return proc.stdout

    def test_valid_request_without_optional_network_profile(self):
        self.run_validator(("ci-test.yaml", VALID))

    def test_valid_standard_network_profile(self):
        self.run_validator(("ci-test.yaml", VALID + "  networkProfile: standard\n"))

    def test_invalid_size_rejected(self):
        output = self.run_validator(("ci-test.yaml", VALID.replace("size: small", "size: large")), expected_success=False)
        self.assertIn("size", output)

    def test_invalid_network_profile_rejected(self):
        output = self.run_validator(("ci-test.yaml", VALID + "  networkProfile: unlimited\n"), expected_success=False)
        self.assertIn("networkProfile", output)

    def test_missing_team_rejected(self):
        self.run_validator(("ci-test.yaml", VALID.replace("  team: payments\n", "")), expected_success=False)

    def test_unknown_spec_key_rejected(self):
        self.run_validator(("ci-test.yaml", VALID + "  unexpected: true\n"), expected_success=False)

    def test_duplicate_yaml_key_rejected(self):
        self.run_validator(("ci-test.yaml", VALID + "  size: medium\n"), expected_success=False)

    def test_multiple_docs_rejected(self):
        self.run_validator(("ci-test.yaml", VALID + "---\n" + VALID), expected_success=False)

    def test_duplicate_environment_names_rejected(self):
        self.run_validator(("one.yaml", VALID), ("two.yaml", VALID), expected_success=False)

    def test_namespace_field_rejected_for_cluster_scoped_xr(self):
        self.run_validator(("ci-test.yaml", VALID.replace("  name: ci-test\n", "  name: ci-test\n  namespace: default\n")), expected_success=False)

    def test_nested_requests_rejected_as_unsynced(self):
        self.run_validator(("subdir/ci-test.yaml", VALID), expected_success=False)

    def test_yml_rejected_as_unsynced(self):
        self.run_validator(("ci-test.yml", VALID), expected_success=False)

    def test_empty_directory_is_allowed_for_prune(self):
        self.run_validator()


if __name__ == "__main__":
    unittest.main()
