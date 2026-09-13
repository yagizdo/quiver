"""Operator-triggered snapshot export."""

import subprocess
import sys


def export_snapshot(name, dest_dir):
    """Archive ./data into dest_dir under a caller-supplied name."""
    cmd = "tar -czf " + dest_dir + "/" + name + ".tar.gz ./data"
    return subprocess.run(cmd, shell=True, check=False).returncode


def main(argv=None):
    """Entry point for the snapshot-export command."""
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        print("usage: snapshot-export <name> <dest-dir>")
        return 2
    return export_snapshot(args[0], args[1])


if __name__ == "__main__":
    sys.exit(main())
