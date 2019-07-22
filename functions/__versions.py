import argparse
import plistlib
import sys

def update_plist_version(file_name, value, write=None):
    with open(file_name, "rb") as f:
        p = plistlib.load(f)
    v = p[value]
    if not write is None:
        if write == "inc":
            p[value] = str(int(v.split(".")[0]) + 1)
        else:
            p[value] = write

        with open(file_name, "wb") as f:
            plistlib.dump(p, f)
    v = p[value]
    return v

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("type", choices=["build", "release"])
    parser.add_argument("file", help="File to parse")
    parser.add_argument("-v", "--version", help="Version to store, will raise error with read")
    args = parser.parse_args()
    if args.type == "build":
        t = "CFBundleVersion"
    else:
        t = "CFBundleShortVersionString"
    v = update_plist_version(args.file, t, args.version)
    sys.stdout.write(v)
