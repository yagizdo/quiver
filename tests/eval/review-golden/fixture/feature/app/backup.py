"""Operator-triggered snapshot export."""

import subprocess


def export_snapshot(name, dest_dir):
    """Archive ./data into dest_dir under a caller-supplied name."""
    cmd = "tar -czf " + dest_dir + "/" + name + ".tar.gz ./data"
    return subprocess.run(cmd, shell=True, check=False).returncode
