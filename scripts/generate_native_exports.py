#!/usr/bin/env python3

import pathlib
import re
import sys


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: generate_native_exports.py "
            "<vev.h> <vev_abi.kvist> <darwin|linux|windows> <output>"
        )

    header_name, abi_name, platform, output_name = sys.argv[1:]
    header = pathlib.Path(header_name).read_text()
    symbols = sorted(set(re.findall(r"\b(vev_[A-Za-z0-9_]+)\s*\(", header)))
    if not symbols:
        raise SystemExit("no public vev_* functions found")

    abi = pathlib.Path(abi_name).read_text()
    implemented = {
        symbol.replace("-", "_")
        for symbol in re.findall(
            r"@export\s*\n\(defn\s+(vev_[A-Za-z0-9_-]+)", abi
        )
    }
    declared = set(symbols)
    missing_declarations = sorted(implemented - declared)
    missing_implementations = sorted(declared - implemented)
    if missing_declarations or missing_implementations:
        messages = []
        if missing_declarations:
            messages.append(
                "ABI exports missing from vev.h: "
                + ", ".join(missing_declarations)
            )
        if missing_implementations:
            messages.append(
                "vev.h declarations missing ABI exports: "
                + ", ".join(missing_implementations)
            )
        raise SystemExit("\n".join(messages))

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
        rendered = "EXPORTS\n" + "\n".join(lines) + "\n"
    else:
        raise SystemExit(f"unsupported export-list platform: {platform}")

    pathlib.Path(output_name).write_text(rendered)


if __name__ == "__main__":
    main()
