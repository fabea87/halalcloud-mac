"""Rough Swift/JSON structural checks that do not need a Swift toolchain."""
import pathlib
import sys


def strip_noise(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
        elif c == '"':
            triple = src[i:i + 3] == '"""'
            i += 3 if triple else 1
            while i < n:
                if triple and src[i:i + 3] == '"""':
                    i += 3
                    break
                if not triple and src[i] == '"':
                    i += 1
                    break
                if src[i] == chr(92):
                    i += 1
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main(root: str) -> int:
    failures = 0
    files = sorted(pathlib.Path(root).rglob("*.swift"))
    for path in files:
        code = strip_noise(path.read_text(encoding="utf-8"))
        for open_c, close_c in [("{", "}"), ("(", ")"), ("[", "]")]:
            if code.count(open_c) != code.count(close_c):
                print(
                    "UNBALANCED %s%s in %s: %d vs %d"
                    % (open_c, close_c, path, code.count(open_c), code.count(close_c))
                )
                failures += 1
        if "\t" in code:
            print("TAB INDENT in %s" % path)
            failures += 1
    print("checked %d Swift files, %d problem(s)" % (len(files), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
