#!/usr/bin/env python3
"""
parse_yaml.py
=============
Minimal YAML accessor for the SuSiEx pipeline. Reads a YAML file and prints
the requested value(s) to stdout in a bash-friendly format.

Modes
-----
    get <yaml_file> <key_path>
        Print a scalar value at the given dotted key path.
        Example: get pipeline.yaml susiex.threads

    list <yaml_file> <key_path> <field>
        Print one line per item in a list at <key_path>, showing the
        named <field>. Useful for iterating cohorts in bash.
        Example: list cohorts.yaml cohorts name

    row <yaml_file> <key_path> <index> [field1 field2 ...]
        Print tab-separated fields from one item in a list at <key_path>.
        If no fields are given, prints all fields.
        Example: row cohorts.yaml cohorts 0 name n_gwas bim_prefix

    count <yaml_file> <key_path>
        Print the number of items in a list at <key_path>.

Requires PyYAML. Install with: pip install pyyaml
"""
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write("[parse_yaml.py] ERROR: PyYAML not installed. Run: pip install pyyaml\n")
    sys.exit(1)


def load(path):
    with open(path) as fh:
        return yaml.safe_load(fh)


def walk(data, key_path):
    """Walk a dotted key path through nested dicts."""
    if not key_path:
        return data
    cur = data
    for key in key_path.split("."):
        if cur is None:
            sys.stderr.write(f"[parse_yaml.py] ERROR: key path '{key_path}' hits None at '{key}'\n")
            sys.exit(2)
        if not isinstance(cur, dict) or key not in cur:
            sys.stderr.write(f"[parse_yaml.py] ERROR: key '{key}' not found in path '{key_path}'\n")
            sys.exit(2)
        cur = cur[key]
    return cur


def cmd_get(args):
    yaml_file, key_path = args[0], args[1]
    val = walk(load(yaml_file), key_path)
    if isinstance(val, bool):
        print("true" if val else "false")
    elif val is None:
        print("")
    else:
        print(val)


def cmd_list(args):
    yaml_file, key_path, field = args[0], args[1], args[2]
    items = walk(load(yaml_file), key_path)
    if not isinstance(items, list):
        sys.stderr.write(f"[parse_yaml.py] ERROR: '{key_path}' is not a list\n")
        sys.exit(2)
    for item in items:
        if not isinstance(item, dict) or field not in item:
            sys.stderr.write(f"[parse_yaml.py] ERROR: item missing field '{field}'\n")
            sys.exit(2)
        print(item[field])


def cmd_row(args):
    yaml_file, key_path, idx = args[0], args[1], int(args[2])
    fields = args[3:]
    items = walk(load(yaml_file), key_path)
    if not isinstance(items, list):
        sys.stderr.write(f"[parse_yaml.py] ERROR: '{key_path}' is not a list\n")
        sys.exit(2)
    if idx < 0 or idx >= len(items):
        sys.stderr.write(f"[parse_yaml.py] ERROR: index {idx} out of range (len={len(items)})\n")
        sys.exit(2)
    item = items[idx]
    if not fields:
        fields = list(item.keys())
    out = []
    for f in fields:
        if f not in item:
            sys.stderr.write(f"[parse_yaml.py] ERROR: field '{f}' not in item\n")
            sys.exit(2)
        v = item[f]
        if isinstance(v, bool):
            out.append("true" if v else "false")
        elif v is None:
            out.append("")
        else:
            out.append(str(v))
    print("\t".join(out))


def cmd_count(args):
    yaml_file, key_path = args[0], args[1]
    items = walk(load(yaml_file), key_path)
    if not isinstance(items, list):
        sys.stderr.write(f"[parse_yaml.py] ERROR: '{key_path}' is not a list\n")
        sys.exit(2)
    print(len(items))


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__)
        sys.exit(1)
    mode = sys.argv[1]
    args = sys.argv[2:]
    dispatch = {"get": cmd_get, "list": cmd_list, "row": cmd_row, "count": cmd_count}
    if mode not in dispatch:
        sys.stderr.write(f"[parse_yaml.py] ERROR: unknown mode '{mode}'\n")
        sys.stderr.write(__doc__)
        sys.exit(1)
    dispatch[mode](args)


if __name__ == "__main__":
    main()
