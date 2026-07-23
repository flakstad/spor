#!/usr/bin/env python3

import pathlib
import re
import sys


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: generate_native_exports.py <vev.h> <darwin|linux|windows> <output>"
        )

    header_name, platform, output_name = sys.argv[1:]
    header = pathlib.Path(header_name).read_text()
    symbols = sorted(set(re.findall(r"\b(vev_[A-Za-z0-9_]+)\s*\(", header)))
    if not symbols:
        raise SystemExit("no public vev_* functions found")

    if platform == "darwin":
        lines = [f"_{symbol}" for symbol in symbols]
        lines.extend(["__odin_entry_point", "__odin_exit_point"])
        rendered = "\n".join(lines) + "\n"
    elif platform == "linux":
        globals_ = "\n".join(f"    {symbol};" for symbol in symbols)
        rendered = (
            "{\n"
            "  global:\n"
            f"{globals_}\n"
            "    _odin_entry_point;\n"
            "    _odin_exit_point;\n"
            "  local: *;\n"
            "};\n"
        )
    elif platform == "windows":
        lines = [f"  {symbol}" for symbol in symbols]
        lines.extend(["  _odin_entry_point", "  _odin_exit_point"])
        rendered = "EXPORTS\n" + "\n".join(lines) + "\n"
    else:
        raise SystemExit(f"unsupported export-list platform: {platform}")

    pathlib.Path(output_name).write_text(rendered)


if __name__ == "__main__":
    main()
