# Copyright (c) Andreas Flakstad and VevDB contributors
# SPDX-License-Identifier: EPL-2.0

from __future__ import annotations

import ctypes
import os
import pathlib
import platform
import sys
import uuid
from datetime import datetime, timezone
from dataclasses import dataclass
from typing import Any


VEV_VALUE_NIL = 0
VEV_VALUE_ENTITY = 1
VEV_VALUE_STRING = 2
VEV_VALUE_INT = 3
VEV_VALUE_FLOAT = 4
VEV_VALUE_BOOL = 5
VEV_VALUE_KEYWORD = 6
VEV_VALUE_SYMBOL = 7
VEV_VALUE_VECTOR = 8
VEV_VALUE_MAP = 9
VEV_VALUE_UUID = 10
VEV_VALUE_INSTANT = 12

VEV_RESULT_VISIT_ROW_BEGIN = 1
VEV_RESULT_VISIT_VALUE = 2
VEV_RESULT_VISIT_PULL = 3
VEV_RESULT_VISIT_ROW_END = 4

VEV_COLUMN_BATCH_NONE = 0
VEV_COLUMN_BATCH_ENTITY = 1
VEV_COLUMN_BATCH_STRING = 2
VEV_COLUMN_BATCH_ENTITY_INT = 3
VEV_COLUMN_BATCH_ENTITY_STRING_INT = 4
VEV_COLUMN_BATCH_INT = 5
VEV_COLUMN_BATCH_ENTITY_STRING = 6
VEV_COLUMN_BATCH_STRING_INT = 7
VEV_COLUMN_BATCH_STRING_STRING = 8

VEV_COLUMN_ENTITY = 1
VEV_COLUMN_STRING = 2
VEV_COLUMN_INT = 3
VEV_COLUMN_MIXED = 4
VEV_COLUMN_BOOL = 5
VEV_COLUMN_FLOAT = 6
VEV_COLUMN_VALUE = 7
VEV_COLUMN_KEYWORD = 8
VEV_COLUMN_SYMBOL = 9
VEV_COLUMN_UUID = 10
VEV_COLUMN_INSTANT = 11

RESULT_VISIT_FN = ctypes.CFUNCTYPE(
    ctypes.c_bool,
    ctypes.c_void_p,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_void_p,
)


@dataclass(frozen=True)
class Entity:
    id: int


@dataclass(frozen=True)
class LookupRef:
    attr: str
    value: object


@dataclass(frozen=True)
class TupleInput:
    values: tuple[object, ...]


@dataclass(frozen=True)
class TypedCollection:
    value_type: str
    values: tuple[object, ...] = ()


@dataclass(frozen=True)
class TypedTuple:
    value_type: str
    values: tuple[object, ...] = ()


@dataclass(frozen=True)
class Relation:
    rows: tuple[tuple[object, ...], ...]


@dataclass(frozen=True)
class TypedRelation:
    value_type: str
    width: int
    rows: tuple[tuple[object, ...], ...] = ()


@dataclass(frozen=True)
class PullPattern:
    edn: str


@dataclass(frozen=True)
class DBSource:
    name: str
    db: "DB"


class VevError(RuntimeError):
    pass


def _platform_library_name() -> str:
    if sys.platform == "darwin":
        return "libvev.dylib"
    if sys.platform.startswith("linux"):
        return "libvev.so"
    if sys.platform in ("win32", "cygwin"):
        return "vev.dll"
    return "libvev"


def _platform_id() -> str:
    if sys.platform == "darwin":
        os_name = "darwin"
    elif sys.platform.startswith("linux"):
        os_name = "linux"
    elif sys.platform in ("win32", "cygwin"):
        os_name = "windows"
    else:
        os_name = sys.platform

    machine = platform.machine().lower()
    if machine in ("arm64", "aarch64"):
        arch = "aarch64"
    elif machine in ("x86_64", "amd64"):
        arch = "x86_64"
    else:
        arch = machine or "unknown"
    return f"{os_name}-{arch}"


def _default_library_path() -> pathlib.Path:
    env_path = os.environ.get("VEV_LIB")
    if env_path:
        return pathlib.Path(env_path)

    library = _platform_library_name()
    root = pathlib.Path(__file__).resolve().parents[2]
    local = root / "build" / "lib" / library
    if local.exists():
        return local

    bundled = pathlib.Path(__file__).resolve().parent / "native" / _platform_id() / library
    if bundled.exists():
        return bundled

    return local


def _bytes(text: str) -> bytes:
    return text.encode("utf-8")


def _value_matches_type(value: object, value_type: str) -> bool:
    if value_type == "entity":
        return isinstance(value, Entity)
    if value_type == "bool":
        return isinstance(value, bool)
    if value_type == "int":
        return isinstance(value, int) and not isinstance(value, bool)
    if value_type == "string":
        return isinstance(value, str)
    return False


class Library:
    def __init__(self, path: str | pathlib.Path | None = None):
        self.path = pathlib.Path(path) if path is not None else _default_library_path()
        self._dll_directories: list[Any] = []
        if os.name == "nt" and hasattr(os, "add_dll_directory"):
            candidates = [self.path.resolve().parent]
            candidates.extend(
                pathlib.Path(entry)
                for entry in os.environ.get("PATH", "").split(os.pathsep)
                if entry
            )
            seen: set[pathlib.Path] = set()
            for directory in candidates:
                directory = directory.resolve()
                if directory in seen or not directory.is_dir():
                    continue
                seen.add(directory)
                self._dll_directories.append(os.add_dll_directory(str(directory)))
        self.lib = ctypes.CDLL(str(self.path))
        self._configure()

    def create_conn(self) -> "Connection":
        return Connection(self)

    def connect(self, uri: str | pathlib.Path) -> "DurableConnection":
        return DurableConnection(self, uri)

    def open_sqlite(self, path: str | pathlib.Path) -> "SQLiteConnection":
        return SQLiteConnection(self, path)

    def _configure(self) -> None:
        lib = self.lib

        lib.vev_version.restype = ctypes.c_char_p

        lib.vev_conn_open_memory.restype = ctypes.c_void_p
        lib.vev_conn_close.argtypes = [ctypes.c_void_p]
        lib.vev_conn_db.argtypes = [ctypes.c_void_p]
        lib.vev_conn_db.restype = ctypes.c_void_p
        lib.vev_conn_from_db.argtypes = [ctypes.c_void_p]
        lib.vev_conn_from_db.restype = ctypes.c_void_p
        lib.vev_connect.argtypes = [ctypes.c_char_p]
        lib.vev_connect.restype = ctypes.c_void_p
        lib.vev_connection_ok.argtypes = [ctypes.c_void_p]
        lib.vev_connection_ok.restype = ctypes.c_bool
        lib.vev_connection_error.argtypes = [ctypes.c_void_p]
        lib.vev_connection_error.restype = ctypes.c_void_p
        lib.vev_connection_backend.argtypes = [ctypes.c_void_p]
        lib.vev_connection_backend.restype = ctypes.c_void_p
        lib.vev_connection_path.argtypes = [ctypes.c_void_p]
        lib.vev_connection_path.restype = ctypes.c_void_p
        lib.vev_connection_basis_t.argtypes = [ctypes.c_void_p]
        lib.vev_connection_basis_t.restype = ctypes.c_ulonglong
        lib.vev_connection_tx_count.argtypes = [ctypes.c_void_p]
        lib.vev_connection_tx_count.restype = ctypes.c_ulonglong
        lib.vev_connection_tx_ids.argtypes = [ctypes.c_void_p]
        lib.vev_connection_tx_ids.restype = ctypes.c_void_p
        lib.vev_connection_info_edn.argtypes = [ctypes.c_void_p]
        lib.vev_connection_info_edn.restype = ctypes.c_void_p
        lib.vev_connection_close.argtypes = [ctypes.c_void_p]
        lib.vev_connection_db.argtypes = [ctypes.c_void_p]
        lib.vev_connection_db.restype = ctypes.c_void_p
        lib.vev_connection_transact_edn_report.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        lib.vev_connection_transact_edn_report.restype = ctypes.c_void_p
        lib.vev_connection_tx_commit_many_report.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_int,
        ]
        lib.vev_connection_tx_commit_many_report.restype = ctypes.c_void_p
        lib.vev_connection_tx_commit_logical_many_reports.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_int,
        ]
        lib.vev_connection_tx_commit_logical_many_reports.restype = ctypes.c_void_p
        lib.vev_connection_transact_many_edn_reports.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_connection_transact_many_edn_reports.restype = ctypes.c_void_p
        lib.vev_sqlite_conn_open.argtypes = [ctypes.c_char_p]
        lib.vev_sqlite_conn_open.restype = ctypes.c_void_p
        lib.vev_sqlite_conn_ok.argtypes = [ctypes.c_void_p]
        lib.vev_sqlite_conn_ok.restype = ctypes.c_bool
        lib.vev_sqlite_conn_error.argtypes = [ctypes.c_void_p]
        lib.vev_sqlite_conn_error.restype = ctypes.c_void_p
        lib.vev_sqlite_conn_close.argtypes = [ctypes.c_void_p]
        lib.vev_sqlite_conn_db.argtypes = [ctypes.c_void_p]
        lib.vev_sqlite_conn_db.restype = ctypes.c_void_p
        lib.vev_sqlite_conn_transact_edn_report.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        lib.vev_sqlite_conn_transact_edn_report.restype = ctypes.c_void_p
        lib.vev_sqlite_conn_tx_commit_many_report.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_int,
        ]
        lib.vev_sqlite_conn_tx_commit_many_report.restype = ctypes.c_void_p
        lib.vev_sqlite_conn_tx_commit_logical_many_reports.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_int,
        ]
        lib.vev_sqlite_conn_tx_commit_logical_many_reports.restype = ctypes.c_void_p
        lib.vev_sqlite_conn_transact_many_edn_reports.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_sqlite_conn_transact_many_edn_reports.restype = ctypes.c_void_p
        lib.vev_db_release.argtypes = [ctypes.c_void_p]
        lib.vev_with_edn.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_with_edn.restype = ctypes.c_void_p
        lib.vev_with_edn_report.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_with_edn_report.restype = ctypes.c_void_p
        lib.vev_db_with_edn.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_db_with_edn.restype = ctypes.c_void_p
        lib.vev_u64_array_free.argtypes = [ctypes.c_void_p]
        lib.vev_u64_array_count.argtypes = [ctypes.c_void_p]
        lib.vev_u64_array_count.restype = ctypes.c_int
        lib.vev_u64_array_value.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_u64_array_value.restype = ctypes.c_ulonglong
        lib.vev_db_entity.argtypes = [ctypes.c_void_p, ctypes.c_ulonglong]
        lib.vev_db_entity.restype = ctypes.c_void_p
        lib.vev_db_entity_lookup_ref_string.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_db_entity_lookup_ref_string.restype = ctypes.c_void_p
        lib.vev_db_entity_ident.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_db_entity_ident.restype = ctypes.c_void_p
        lib.vev_entity_free.argtypes = [ctypes.c_void_p]
        lib.vev_entity_found.argtypes = [ctypes.c_void_p]
        lib.vev_entity_found.restype = ctypes.c_bool
        lib.vev_entity_id.argtypes = [ctypes.c_void_p]
        lib.vev_entity_id.restype = ctypes.c_ulonglong
        lib.vev_entity_contains.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_entity_contains.restype = ctypes.c_bool
        lib.vev_entity_get.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_entity_get.restype = ctypes.c_void_p
        lib.vev_entity_values.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_entity_values.restype = ctypes.c_void_p
        lib.vev_entity_ref.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_entity_ref.restype = ctypes.c_void_p
        lib.vev_entity_refs.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_entity_refs.restype = ctypes.c_void_p
        lib.vev_entity_touch.argtypes = [ctypes.c_void_p]
        lib.vev_entity_touch.restype = ctypes.c_void_p

        lib.vev_string_free.argtypes = [ctypes.c_void_p]

        lib.vev_transact_edn.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_transact_edn.restype = ctypes.c_void_p
        lib.vev_transact_edn_report.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_transact_edn_report.restype = ctypes.c_void_p
        lib.vev_tx_report_free.argtypes = [ctypes.c_void_p]
        lib.vev_tx_report_value.argtypes = [ctypes.c_void_p]
        lib.vev_tx_report_value.restype = ctypes.c_void_p
        lib.vev_tx_report_edn.argtypes = [ctypes.c_void_p]
        lib.vev_tx_report_edn.restype = ctypes.c_void_p
        lib.vev_tx_report_db_before.argtypes = [ctypes.c_void_p]
        lib.vev_tx_report_db_before.restype = ctypes.c_void_p
        lib.vev_tx_report_db_after.argtypes = [ctypes.c_void_p]
        lib.vev_tx_report_db_after.restype = ctypes.c_void_p
        lib.vev_tx_report_array_free.argtypes = [ctypes.c_void_p]
        lib.vev_tx_report_array_count.argtypes = [ctypes.c_void_p]
        lib.vev_tx_report_array_count.restype = ctypes.c_int
        lib.vev_tx_report_array_get.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_tx_report_array_get.restype = ctypes.c_void_p
        lib.vev_tx_create.argtypes = [ctypes.c_int]
        lib.vev_tx_create.restype = ctypes.c_void_p
        lib.vev_tx_free.argtypes = [ctypes.c_void_p]
        lib.vev_tx_add_string.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulonglong,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_tx_add_string.restype = ctypes.c_bool
        lib.vev_tx_add_keyword.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulonglong,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_tx_add_keyword.restype = ctypes.c_bool
        lib.vev_tx_add_symbol.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulonglong,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_tx_add_symbol.restype = ctypes.c_bool
        lib.vev_tx_add_entity.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulonglong,
            ctypes.c_char_p,
            ctypes.c_ulonglong,
        ]
        lib.vev_tx_add_entity.restype = ctypes.c_bool
        lib.vev_tx_add_int.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulonglong,
            ctypes.c_char_p,
            ctypes.c_longlong,
        ]
        lib.vev_tx_add_int.restype = ctypes.c_bool
        lib.vev_tx_add_bool.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulonglong,
            ctypes.c_char_p,
            ctypes.c_bool,
        ]
        lib.vev_tx_add_bool.restype = ctypes.c_bool
        lib.vev_query_edn.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_query_edn.restype = ctypes.c_void_p
        lib.vev_query_edn_with_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_query_edn_with_inputs.restype = ctypes.c_void_p

        lib.vev_prepare_query_edn.argtypes = [ctypes.c_char_p]
        lib.vev_prepare_query_edn.restype = ctypes.c_void_p
        lib.vev_prepare_query_edn_with_sources.argtypes = [
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_prepare_query_edn_with_sources.restype = ctypes.c_void_p
        lib.vev_prepared_query_ok.argtypes = [ctypes.c_void_p]
        lib.vev_prepared_query_ok.restype = ctypes.c_bool
        lib.vev_prepared_query_error.argtypes = [ctypes.c_void_p]
        lib.vev_prepared_query_error.restype = ctypes.c_void_p
        lib.vev_prepared_query_edn.argtypes = [ctypes.c_void_p]
        lib.vev_prepared_query_edn.restype = ctypes.c_void_p
        lib.vev_parse_clause_edn.argtypes = [ctypes.c_char_p]
        lib.vev_parse_clause_edn.restype = ctypes.c_void_p
        lib.vev_prepared_query_free.argtypes = [ctypes.c_void_p]

        lib.vev_stmt_create.argtypes = [ctypes.c_void_p]
        lib.vev_stmt_create.restype = ctypes.c_void_p
        lib.vev_stmt_clear.argtypes = [ctypes.c_void_p]
        lib.vev_stmt_free.argtypes = [ctypes.c_void_p]
        lib.vev_stmt_error.argtypes = [ctypes.c_void_p]
        lib.vev_stmt_error.restype = ctypes.c_void_p
        lib.vev_stmt_bind_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_stmt_bind_string.restype = ctypes.c_bool
        lib.vev_stmt_bind_keyword.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_stmt_bind_keyword.restype = ctypes.c_bool
        lib.vev_stmt_bind_symbol.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.vev_stmt_bind_symbol.restype = ctypes.c_bool
        lib.vev_stmt_bind_entity.argtypes = [ctypes.c_void_p, ctypes.c_ulonglong]
        lib.vev_stmt_bind_entity.restype = ctypes.c_bool
        lib.vev_stmt_bind_int.argtypes = [ctypes.c_void_p, ctypes.c_longlong]
        lib.vev_stmt_bind_int.restype = ctypes.c_bool
        lib.vev_stmt_bind_bool.argtypes = [ctypes.c_void_p, ctypes.c_bool]
        lib.vev_stmt_bind_bool.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_string.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_stmt_bind_lookup_ref_string.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_keyword.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_stmt_bind_lookup_ref_keyword.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_entity.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_ulonglong,
        ]
        lib.vev_stmt_bind_lookup_ref_entity.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_int.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_longlong,
        ]
        lib.vev_stmt_bind_lookup_ref_int.restype = ctypes.c_bool
        lib.vev_stmt_bind_string_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_string_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_entity_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_ulonglong),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_entity_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_int_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_longlong),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_int_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_bool_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_bool),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_bool_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_string_tuple.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_string_tuple.restype = ctypes.c_bool
        lib.vev_stmt_bind_entity_tuple.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_ulonglong),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_entity_tuple.restype = ctypes.c_bool
        lib.vev_stmt_bind_int_tuple.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_longlong),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_int_tuple.restype = ctypes.c_bool
        lib.vev_stmt_bind_bool_tuple.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_bool),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_bool_tuple.restype = ctypes.c_bool
        lib.vev_stmt_bind_string_relation.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_string_relation.restype = ctypes.c_bool
        lib.vev_stmt_bind_entity_relation.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_ulonglong),
            ctypes.c_int,
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_entity_relation.restype = ctypes.c_bool
        lib.vev_stmt_bind_int_relation.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_longlong),
            ctypes.c_int,
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_int_relation.restype = ctypes.c_bool
        lib.vev_stmt_bind_bool_relation.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_bool),
            ctypes.c_int,
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_bool_relation.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_string_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_lookup_ref_string_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_keyword_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_lookup_ref_keyword_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_entity_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_ulonglong),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_lookup_ref_entity_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_lookup_ref_int_collection.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_longlong),
            ctypes.c_int,
        ]
        lib.vev_stmt_bind_lookup_ref_int_collection.restype = ctypes.c_bool
        lib.vev_stmt_bind_pull_pattern_edn.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        lib.vev_stmt_bind_pull_pattern_edn.restype = ctypes.c_bool
        lib.vev_stmt_bind_db_source.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_void_p,
        ]
        lib.vev_stmt_bind_db_source.restype = ctypes.c_bool

        lib.vev_query_prepared_with_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        lib.vev_query_prepared_with_inputs.restype = ctypes.c_void_p
        lib.vev_query_prepared_result_with_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        lib.vev_query_prepared_result_with_inputs.restype = ctypes.c_void_p
        lib.vev_query_prepared_result_with_rules_text_and_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_query_prepared_result_with_rules_text_and_inputs.restype = (
            ctypes.c_void_p
        )
        lib.vev_query_stmt_result.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        lib.vev_query_stmt_result.restype = ctypes.c_void_p
        lib.vev_query_db_stmt_result.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        lib.vev_query_db_stmt_result.restype = ctypes.c_void_p
        lib.vev_query_stmt_column_batch.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        lib.vev_query_stmt_column_batch.restype = ctypes.c_void_p
        lib.vev_query_db_stmt_column_batch.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        lib.vev_query_db_stmt_column_batch.restype = ctypes.c_void_p
        lib.vev_query_stmt_visit.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            RESULT_VISIT_FN,
            ctypes.c_void_p,
        ]
        lib.vev_query_stmt_visit.restype = ctypes.c_bool
        lib.vev_query_db_stmt_visit.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            RESULT_VISIT_FN,
            ctypes.c_void_p,
        ]
        lib.vev_query_db_stmt_visit.restype = ctypes.c_bool
        lib.vev_query_db_prepared_result_with_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        lib.vev_query_db_prepared_result_with_inputs.restype = ctypes.c_void_p
        lib.vev_query_db_prepared_result_with_rules_text_and_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_query_db_prepared_result_with_rules_text_and_inputs.restype = (
            ctypes.c_void_p
        )
        lib.vev_query_db_prepared_column_batch_with_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        lib.vev_query_db_prepared_column_batch_with_inputs.restype = ctypes.c_void_p
        lib.vev_column_batch_free.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_kind.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_kind.restype = ctypes.c_int
        lib.vev_column_batch_count.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_count.restype = ctypes.c_int
        lib.vev_column_batch_column_count.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_column_count.restype = ctypes.c_int
        lib.vev_column_batch_column_kind.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_column_batch_column_kind.restype = ctypes.c_int
        lib.vev_column_batch_entities_data.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_entities_data.restype = ctypes.c_void_p
        lib.vev_column_batch_ints_data.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_ints_data.restype = ctypes.c_void_p
        lib.vev_column_batch_string_data_array.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_string_data_array.restype = ctypes.c_void_p
        lib.vev_column_batch_string_lengths_data.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_string_lengths_data.restype = ctypes.c_void_p
        lib.vev_column_batch_second_string_data_array.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_second_string_data_array.restype = ctypes.c_void_p
        lib.vev_column_batch_second_string_lengths_data.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_second_string_lengths_data.restype = ctypes.c_void_p
        lib.vev_column_batch_column_entities_data.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_entities_data.restype = ctypes.c_void_p
        lib.vev_column_batch_column_ints_data.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_ints_data.restype = ctypes.c_void_p
        lib.vev_column_batch_column_floats_data.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_floats_data.restype = ctypes.c_void_p
        lib.vev_column_batch_column_bools_data.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_bools_data.restype = ctypes.c_void_p
        lib.vev_column_batch_column_value_kinds_data.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_value_kinds_data.restype = ctypes.c_void_p
        lib.vev_column_batch_column_values_data.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_values_data.restype = ctypes.c_void_p
        lib.vev_column_batch_column_string_data_array.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_string_data_array.restype = ctypes.c_void_p
        lib.vev_column_batch_column_string_lengths_data.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        lib.vev_column_batch_column_string_lengths_data.restype = ctypes.c_void_p
        lib.vev_column_batch_string_dictionary_count.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_string_dictionary_count.restype = ctypes.c_int
        lib.vev_column_batch_string_dictionary_data_array.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_string_dictionary_data_array.restype = ctypes.c_void_p
        lib.vev_column_batch_string_dictionary_lengths_data.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_string_dictionary_lengths_data.restype = ctypes.c_void_p
        lib.vev_column_batch_string_indices_data.argtypes = [ctypes.c_void_p]
        lib.vev_column_batch_string_indices_data.restype = ctypes.c_void_p
        lib.vev_pull_edn.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_ulonglong,
        ]
        lib.vev_pull_edn.restype = ctypes.c_void_p
        lib.vev_prepare_pull_pattern_edn.argtypes = [ctypes.c_char_p]
        lib.vev_prepare_pull_pattern_edn.restype = ctypes.c_void_p
        lib.vev_prepared_pull_pattern_ok.argtypes = [ctypes.c_void_p]
        lib.vev_prepared_pull_pattern_ok.restype = ctypes.c_bool
        lib.vev_prepared_pull_pattern_error.argtypes = [ctypes.c_void_p]
        lib.vev_prepared_pull_pattern_error.restype = ctypes.c_void_p
        lib.vev_prepared_pull_pattern_edn.argtypes = [ctypes.c_void_p]
        lib.vev_prepared_pull_pattern_edn.restype = ctypes.c_void_p
        lib.vev_prepared_pull_pattern_free.argtypes = [ctypes.c_void_p]
        lib.vev_pull_prepared.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_ulonglong,
        ]
        lib.vev_pull_prepared.restype = ctypes.c_void_p
        lib.vev_pull_lookup_ref_string_edn.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_pull_lookup_ref_string_edn.restype = ctypes.c_void_p
        lib.vev_pull_many_edn.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_ulonglong),
            ctypes.c_int,
        ]
        lib.vev_pull_many_edn.restype = ctypes.c_void_p
        lib.vev_pull_many_prepared.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_ulonglong),
            ctypes.c_int,
        ]
        lib.vev_pull_many_prepared.restype = ctypes.c_void_p
        lib.vev_pull_many_lookup_ref_string_edn.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_pull_many_lookup_ref_string_edn.restype = ctypes.c_void_p
        lib.vev_pull_many_lookup_ref_string_prepared.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.c_int,
        ]
        lib.vev_pull_many_lookup_ref_string_prepared.restype = ctypes.c_void_p
        lib.vev_value_handle_free.argtypes = [ctypes.c_void_p]
        lib.vev_value_handle_value.argtypes = [ctypes.c_void_p]
        lib.vev_value_handle_value.restype = ctypes.c_void_p
        lib.vev_value_handle_edn.argtypes = [ctypes.c_void_p]
        lib.vev_value_handle_edn.restype = ctypes.c_void_p
        lib.vev_db_query_value_with_inputs.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        lib.vev_db_query_value_with_inputs.restype = ctypes.c_void_p

        lib.vev_result_free.argtypes = [ctypes.c_void_p]
        lib.vev_result_ok.argtypes = [ctypes.c_void_p]
        lib.vev_result_ok.restype = ctypes.c_bool
        lib.vev_result_error.argtypes = [ctypes.c_void_p]
        lib.vev_result_error.restype = ctypes.c_void_p
        lib.vev_result_row_count.argtypes = [ctypes.c_void_p]
        lib.vev_result_row_count.restype = ctypes.c_int
        lib.vev_result_value_count.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_result_value_count.restype = ctypes.c_int
        lib.vev_result_value.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        lib.vev_result_value.restype = ctypes.c_void_p
        lib.vev_result_pull_count.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_result_pull_count.restype = ctypes.c_int
        lib.vev_result_pull.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        lib.vev_result_pull.restype = ctypes.c_void_p

        lib.vev_value_kind.argtypes = [ctypes.c_void_p]
        lib.vev_value_kind.restype = ctypes.c_int
        lib.vev_value_entity.argtypes = [ctypes.c_void_p]
        lib.vev_value_entity.restype = ctypes.c_ulonglong
        lib.vev_value_int.argtypes = [ctypes.c_void_p]
        lib.vev_value_int.restype = ctypes.c_longlong
        lib.vev_value_float.argtypes = [ctypes.c_void_p]
        lib.vev_value_float.restype = ctypes.c_double
        lib.vev_value_bool.argtypes = [ctypes.c_void_p]
        lib.vev_value_bool.restype = ctypes.c_bool
        lib.vev_value_text.argtypes = [ctypes.c_void_p]
        lib.vev_value_text.restype = ctypes.c_void_p
        lib.vev_value_edn.argtypes = [ctypes.c_void_p]
        lib.vev_value_edn.restype = ctypes.c_void_p
        lib.vev_value_item_count.argtypes = [ctypes.c_void_p]
        lib.vev_value_item_count.restype = ctypes.c_int
        lib.vev_value_item.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_value_item.restype = ctypes.c_void_p
        lib.vev_value_map_count.argtypes = [ctypes.c_void_p]
        lib.vev_value_map_count.restype = ctypes.c_int
        lib.vev_value_map_key.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_value_map_key.restype = ctypes.c_void_p
        lib.vev_value_map_value.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.vev_value_map_value.restype = ctypes.c_void_p

    def owned_text(self, ptr: int) -> str:
        if not ptr:
            return ""
        try:
            return ctypes.cast(ptr, ctypes.c_char_p).value.decode("utf-8")
        finally:
            self.lib.vev_string_free(ptr)

    def parse_clause_edn(self, clause_edn: str) -> str:
        return self.owned_text(self.lib.vev_parse_clause_edn(_bytes(clause_edn)))

    def prepare_pull_pattern(self, pattern_edn: str) -> "PreparedPullPattern":
        return PreparedPullPattern(self, pattern_edn)

    def value_to_python(self, value: int) -> Any:
        kind = self.lib.vev_value_kind(value)
        if kind == VEV_VALUE_NIL:
            return None
        if kind == VEV_VALUE_ENTITY:
            return Entity(int(self.lib.vev_value_entity(value)))
        if kind == VEV_VALUE_STRING:
            return self.owned_text(self.lib.vev_value_text(value))
        if kind == VEV_VALUE_INT:
            return int(self.lib.vev_value_int(value))
        if kind == VEV_VALUE_FLOAT:
            return float(self.lib.vev_value_float(value))
        if kind == VEV_VALUE_BOOL:
            return bool(self.lib.vev_value_bool(value))
        if kind == VEV_VALUE_KEYWORD:
            return self.owned_text(self.lib.vev_value_text(value))
        if kind == VEV_VALUE_SYMBOL:
            return self.owned_text(self.lib.vev_value_text(value))
        if kind == VEV_VALUE_UUID:
            return uuid.UUID(self.owned_text(self.lib.vev_value_text(value)))
        if kind == VEV_VALUE_INSTANT:
            return datetime.fromtimestamp(
                self.lib.vev_value_int(value) / 1000, tz=timezone.utc
            )
        if kind == VEV_VALUE_VECTOR:
            return [
                self.value_to_python(self.lib.vev_value_item(value, index))
                for index in range(self.lib.vev_value_item_count(value))
            ]
        if kind == VEV_VALUE_MAP:
            return {
                self.value_to_python(
                    self.lib.vev_value_map_key(value, index)
                ): self.value_to_python(
                    self.lib.vev_value_map_value(value, index)
                )
                for index in range(self.lib.vev_value_map_count(value))
            }
        if kind == VEV_VALUE_SET:
            return {
                self._hashable_value(
                    self.value_to_python(self.lib.vev_value_item(value, index))
                )
                for index in range(self.lib.vev_value_item_count(value))
            }
        return self.owned_text(self.lib.vev_value_edn(value))

    @classmethod
    def _hashable_value(cls, value: Any) -> Any:
        if isinstance(value, list):
            return tuple(cls._hashable_value(item) for item in value)
        if isinstance(value, dict):
            return frozenset(
                (cls._hashable_value(key), cls._hashable_value(item))
                for key, item in value.items()
            )
        if isinstance(value, set):
            return frozenset(cls._hashable_value(item) for item in value)
        return value

    def _long_column(self, pointer: int, count: int) -> list[int]:
        if not pointer:
            return []
        array = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_ulonglong))
        return [int(array[index]) for index in range(count)]

    def _int_column(self, pointer: int, count: int) -> list[int]:
        if not pointer:
            return []
        array = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_longlong))
        return [int(array[index]) for index in range(count)]

    def _int32_column(self, pointer: int, count: int) -> list[int]:
        if not pointer:
            return []
        array = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_int))
        return [int(array[index]) for index in range(count)]

    def _float_column(self, pointer: int, count: int) -> list[float]:
        if not pointer:
            return []
        array = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_double))
        return [float(array[index]) for index in range(count)]

    def _bool_column(self, pointer: int, count: int) -> list[bool]:
        if not pointer:
            return []
        array = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_bool))
        return [bool(array[index]) for index in range(count)]

    def _string_column(self, batch: int, count: int) -> list[str]:
        dictionary_count = self.lib.vev_column_batch_string_dictionary_count(batch)
        dictionary_data = self.lib.vev_column_batch_string_dictionary_data_array(batch)
        dictionary_lengths = self.lib.vev_column_batch_string_dictionary_lengths_data(batch)
        string_indices = self.lib.vev_column_batch_string_indices_data(batch)
        if dictionary_count > 0 and dictionary_data and dictionary_lengths and string_indices:
            data_array = ctypes.cast(dictionary_data, ctypes.POINTER(ctypes.c_void_p))
            length_array = ctypes.cast(dictionary_lengths, ctypes.POINTER(ctypes.c_int))
            index_array = ctypes.cast(string_indices, ctypes.POINTER(ctypes.c_int))
            dictionary = [
                ctypes.string_at(data_array[index], length_array[index]).decode("utf-8")
                for index in range(dictionary_count)
            ]
            return [dictionary[index_array[index]] for index in range(count)]

        string_data = self.lib.vev_column_batch_string_data_array(batch)
        string_lengths = self.lib.vev_column_batch_string_lengths_data(batch)
        if not string_data or not string_lengths:
            return []
        data_array = ctypes.cast(string_data, ctypes.POINTER(ctypes.c_void_p))
        length_array = ctypes.cast(string_lengths, ctypes.POINTER(ctypes.c_int))
        return [
            ctypes.string_at(data_array[index], length_array[index]).decode("utf-8")
            for index in range(count)
        ]

    def _second_string_column(self, batch: int, count: int) -> list[str]:
        string_data = self.lib.vev_column_batch_second_string_data_array(batch)
        string_lengths = self.lib.vev_column_batch_second_string_lengths_data(batch)
        if not string_data or not string_lengths:
            return []
        data_array = ctypes.cast(string_data, ctypes.POINTER(ctypes.c_void_p))
        length_array = ctypes.cast(string_lengths, ctypes.POINTER(ctypes.c_int))
        return [
            ctypes.string_at(data_array[index], length_array[index]).decode("utf-8")
            for index in range(count)
        ]

    def _string_column_at(self, batch: int, column: int, count: int) -> list[str]:
        string_data = self.lib.vev_column_batch_column_string_data_array(batch, column)
        string_lengths = self.lib.vev_column_batch_column_string_lengths_data(
            batch, column
        )
        if not string_data or not string_lengths:
            return []
        data_array = ctypes.cast(string_data, ctypes.POINTER(ctypes.c_void_p))
        length_array = ctypes.cast(string_lengths, ctypes.POINTER(ctypes.c_int))
        return [
            ctypes.string_at(data_array[index], length_array[index]).decode("utf-8")
            for index in range(count)
        ]

    def _mixed_column_at(self, batch: int, column: int, count: int) -> list[object]:
        value_kinds = self._int32_column(
            self.lib.vev_column_batch_column_value_kinds_data(batch, column), count
        )
        if len(value_kinds) != count:
            return []
        entities = self._long_column(
            self.lib.vev_column_batch_column_entities_data(batch, column), count
        )
        ints = self._int_column(
            self.lib.vev_column_batch_column_ints_data(batch, column), count
        )
        floats = self._float_column(
            self.lib.vev_column_batch_column_floats_data(batch, column), count
        )
        bools = self._bool_column(
            self.lib.vev_column_batch_column_bools_data(batch, column), count
        )
        strings = self._string_column_at(batch, column, count)
        out: list[object] = []
        for index, kind in enumerate(value_kinds):
            if kind == VEV_VALUE_NIL:
                out.append(None)
            elif kind == VEV_VALUE_ENTITY:
                out.append(Entity(entities[index]))
            elif kind == VEV_VALUE_STRING:
                out.append(strings[index])
            elif kind == VEV_VALUE_INT:
                out.append(ints[index])
            elif kind == VEV_VALUE_FLOAT:
                out.append(floats[index])
            elif kind == VEV_VALUE_BOOL:
                out.append(bools[index])
            elif kind == VEV_VALUE_KEYWORD:
                out.append(Keyword(strings[index]))
            elif kind == VEV_VALUE_SYMBOL:
                out.append(Symbol(strings[index]))
            elif kind == VEV_VALUE_UUID:
                out.append(uuid.UUID(strings[index]))
            elif kind == VEV_VALUE_INSTANT:
                out.append(datetime.fromtimestamp(ints[index] / 1000, tz=timezone.utc))
            else:
                out.append(strings[index])
        return out

    def _value_column_at(self, batch: int, column: int, count: int) -> list[object]:
        values = self.lib.vev_column_batch_column_values_data(batch, column)
        if not values:
            return []
        value_array = ctypes.cast(values, ctypes.POINTER(ctypes.c_void_p))
        return [self.value_to_python(value_array[index]) for index in range(count)]

    def _column_result_from_handle(self, handle: int) -> "ColumnResult | None":
        if not handle:
            return None
        try:
            count = self.lib.vev_column_batch_count(handle)
            column_count = self.lib.vev_column_batch_column_count(handle)
            if column_count <= 0:
                return None
            kinds: list[int] = []
            columns: list[list[object]] = []
            for column in range(column_count):
                kind = self.lib.vev_column_batch_column_kind(handle, column)
                if kind == VEV_COLUMN_ENTITY:
                    kinds.append(kind)
                    columns.append(
                        self._long_column(
                            self.lib.vev_column_batch_column_entities_data(
                                handle, column
                            ),
                            count,
                        )
                    )
                elif kind == VEV_COLUMN_STRING:
                    kinds.append(kind)
                    columns.append(self._string_column_at(handle, column, count))
                elif kind == VEV_COLUMN_KEYWORD:
                    kinds.append(kind)
                    columns.append(
                        [Keyword(value) for value in self._string_column_at(handle, column, count)]
                    )
                elif kind == VEV_COLUMN_SYMBOL:
                    kinds.append(kind)
                    columns.append(
                        [Symbol(value) for value in self._string_column_at(handle, column, count)]
                    )
                elif kind == VEV_COLUMN_UUID:
                    kinds.append(kind)
                    columns.append(
                        [uuid.UUID(value) for value in self._string_column_at(handle, column, count)]
                    )
                elif kind == VEV_COLUMN_INT:
                    kinds.append(kind)
                    columns.append(
                        self._int_column(
                            self.lib.vev_column_batch_column_ints_data(
                                handle, column
                            ),
                            count,
                        )
                    )
                elif kind == VEV_COLUMN_INSTANT:
                    kinds.append(kind)
                    columns.append(
                        [
                            datetime.fromtimestamp(value / 1000, tz=timezone.utc)
                            for value in self._int_column(
                                self.lib.vev_column_batch_column_ints_data(
                                    handle, column
                                ),
                                count,
                            )
                        ]
                    )
                elif kind == VEV_COLUMN_BOOL:
                    kinds.append(kind)
                    columns.append(
                        self._bool_column(
                            self.lib.vev_column_batch_column_bools_data(
                                handle, column
                            ),
                            count,
                        )
                    )
                elif kind == VEV_COLUMN_FLOAT:
                    kinds.append(kind)
                    columns.append(
                        self._float_column(
                            self.lib.vev_column_batch_column_floats_data(
                                handle, column
                            ),
                            count,
                        )
                    )
                elif kind == VEV_COLUMN_MIXED:
                    kinds.append(kind)
                    mixed = self._mixed_column_at(handle, column, count)
                    if len(mixed) != count:
                        return None
                    columns.append(mixed)
                elif kind == VEV_COLUMN_VALUE:
                    kinds.append(kind)
                    values = self._value_column_at(handle, column, count)
                    if len(values) != count:
                        return None
                    columns.append(values)
                else:
                    return None
            return ColumnResult(count, tuple(kinds), tuple(columns))
        finally:
            self.lib.vev_column_batch_free(handle)


_default_library: Library | None = None


def default_library() -> Library:
    global _default_library
    if _default_library is None:
        _default_library = Library()
    return _default_library


def create_conn() -> "Connection":
    return Connection(default_library())


def open_memory() -> "Connection":
    return create_conn()


def connect(uri: str | pathlib.Path) -> "DurableConnection":
    return DurableConnection(default_library(), uri)


def open_sqlite(path: str | pathlib.Path) -> "SQLiteConnection":
    return SQLiteConnection(default_library(), path)


def q(
    query_edn: str,
    source: "Connection | DurableConnection | DB",
    inputs_edn: str = "[]",
) -> Any:
    """Run a one-shot Datalog query.

    Prefer passing an immutable DB snapshot. Passing a connection is accepted as
    a convenience and takes a short-lived DB snapshot for the call.
    """
    if isinstance(source, DB):
        return source.q(query_edn, inputs_edn)
    if isinstance(source, (Connection, DurableConnection)):
        with source.db() as db:
            return db.q(query_edn, inputs_edn)
    raise VevError("q expects a DB, Connection, or DurableConnection")


def parse_clause_edn(clause_edn: str) -> str:
    return default_library().parse_clause_edn(clause_edn)


def prepare_pull_pattern(pattern_edn: str) -> "PreparedPullPattern":
    return default_library().prepare_pull_pattern(pattern_edn)


def tx_builder(capacity: int = 0) -> "TxBuilder":
    return TxBuilder(default_library(), capacity)


class Connection:
    def __init__(self, library: Library, handle: int | None = None):
        self._library = library
        self._handle = handle if handle is not None else library.lib.vev_conn_open_memory()
        if not self._handle:
            raise VevError("failed to open Vev connection")

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_conn_close(self._handle)
            self._handle = None

    def __enter__(self) -> "Connection":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def transact(self, tx_edn: str) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_transact_edn(self._handle, _bytes(tx_edn))
        )

    def transact_report(self, tx_edn: str) -> "TxReport":
        self._require_open()
        handle = self._library.lib.vev_transact_edn_report(
            self._handle, _bytes(tx_edn)
        )
        if not handle:
            raise VevError("failed to transact")
        return TxReport(self._library, handle)

    def query_text(self, query_edn: str, inputs_edn: str | None = None) -> str:
        self._require_open()
        if inputs_edn is None:
            return self._library.owned_text(
                self._library.lib.vev_query_edn(self._handle, _bytes(query_edn))
            )
        return self._library.owned_text(
            self._library.lib.vev_query_edn_with_inputs(
                self._handle, _bytes(query_edn), _bytes(inputs_edn)
            )
        )

    def prepare(
        self, query_edn: str, source_names: list[str] | None = None
    ) -> "PreparedQuery":
        return PreparedQuery(self._library, query_edn, source_names)

    def db(self) -> "DB":
        self._require_open()
        handle = self._library.lib.vev_conn_db(self._handle)
        if not handle:
            raise VevError("failed to retain DB snapshot")
        return DB(self._library, handle)

    @classmethod
    def from_db(cls, db: "DB") -> "Connection":
        """Create a mutable connection from a resident/in-memory DB value.

        Durable DB handles are immutable values; query/pull/with them directly
        instead of converting them back into connections.
        """
        db._require_open()
        handle = db._library.lib.vev_conn_from_db(db._handle)
        if not handle:
            raise VevError("failed to create connection from DB snapshot")
        return cls(db._library, handle)

    def _query_result(self, prepared: "PreparedQuery", inputs_edn: str = "[]") -> "Result":
        self._require_open()
        handle = self._library.lib.vev_query_prepared_result_with_inputs(
            self._handle, prepared._handle, _bytes(inputs_edn)
        )
        return Result(self._library, handle)

    def _query_result_with_rules(
        self, prepared: "PreparedQuery", rules_edn: str, inputs_edn: str = "[]"
    ) -> "Result":
        self._require_open()
        handle = self._library.lib.vev_query_prepared_result_with_rules_text_and_inputs(
            self._handle, prepared._handle, _bytes(rules_edn), _bytes(inputs_edn)
        )
        return Result(self._library, handle)

    def _query_stmt(self, stmt: "Statement") -> "Result":
        self._require_open()
        stmt._require_open()
        handle = self._library.lib.vev_query_stmt_result(self._handle, stmt._handle)
        return Result(self._library, handle)

    def _query_stmt_columns(self, stmt: "Statement") -> "ColumnResult | None":
        self._require_open()
        stmt._require_open()
        handle = self._library.lib.vev_query_stmt_column_batch(
            self._handle, stmt._handle
        )
        return self._library._column_result_from_handle(handle)

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("connection is closed")


class DurableConnection:
    def __init__(self, library: Library, uri: str | pathlib.Path):
        self._library = library
        self._handle = library.lib.vev_connect(_bytes(str(uri)))
        if not self._handle:
            raise VevError("failed to connect Vev durable connection")
        if not library.lib.vev_connection_ok(self._handle):
            error = library.owned_text(library.lib.vev_connection_error(self._handle))
            self.close()
            raise VevError(error)

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_connection_close(self._handle)
            self._handle = None

    def __enter__(self) -> "DurableConnection":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def transact(self, tx_edn: str) -> str:
        with self.transact_report(tx_edn) as report:
            return report.edn()

    def transact_report(self, tx_edn: str) -> "TxReport":
        self._require_open()
        handle = self._library.lib.vev_connection_transact_edn_report(
            self._handle, _bytes(tx_edn)
        )
        if not handle:
            raise VevError("failed to transact")
        return TxReport(self._library, handle)

    def transact_bulk(self, txs: list["TxBuilder"] | tuple["TxBuilder", ...]) -> "TxReport":
        self._require_open()
        handles = _tx_builder_handle_array(txs)
        handle = self._library.lib.vev_connection_tx_commit_many_report(
            self._handle, handles, len(txs)
        )
        if not handle:
            raise VevError("failed to transact bulk tx builders")
        return TxReport(self._library, handle)

    def transact_logical_bulk(
        self, txs: list["TxBuilder"] | tuple["TxBuilder", ...]
    ) -> "TxReportArray":
        self._require_open()
        handles = _tx_builder_handle_array(
            txs, name="transact_logical_bulk", allow_empty=True
        )
        handle = self._library.lib.vev_connection_tx_commit_logical_many_reports(
            self._handle, handles, len(txs)
        )
        if not handle:
            raise VevError("failed to logical-group transact tx builders")
        return TxReportArray(self._library, handle)

    def transact_logical(
        self, txs: list[str] | tuple[str, ...]
    ) -> "TxReportArray":
        self._require_open()
        texts = _edn_text_array(txs, name="transact_logical")
        handle = self._library.lib.vev_connection_transact_many_edn_reports(
            self._handle, texts, len(txs)
        )
        if not handle:
            raise VevError("failed to logical-group transact EDN tx data")
        return TxReportArray(self._library, handle)

    def db(self) -> "DB":
        self._require_open()
        handle = self._library.lib.vev_connection_db(self._handle)
        if not handle:
            raise VevError("failed to retain DB snapshot")
        return DB(self._library, handle)

    def backend(self) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_connection_backend(self._handle)
        )

    def path(self) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_connection_path(self._handle)
        )

    def basis_t(self) -> int:
        self._require_open()
        return int(self._library.lib.vev_connection_basis_t(self._handle))

    def tx_count(self) -> int:
        self._require_open()
        return int(self._library.lib.vev_connection_tx_count(self._handle))

    def tx_ids(self) -> list[int]:
        self._require_open()
        handle = self._library.lib.vev_connection_tx_ids(self._handle)
        if not handle:
            return []
        try:
            count = self._library.lib.vev_u64_array_count(handle)
            return [
                int(self._library.lib.vev_u64_array_value(handle, index))
                for index in range(count)
            ]
        finally:
            self._library.lib.vev_u64_array_free(handle)

    def info_edn(self) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_connection_info_edn(self._handle)
        )

    def prepare(
        self, query_edn: str, source_names: list[str] | None = None
    ) -> "PreparedQuery":
        return PreparedQuery(self._library, query_edn, source_names)

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("durable connection is closed")


class SQLiteConnection:
    def __init__(self, library: Library, path: str | pathlib.Path):
        self._library = library
        self._handle = library.lib.vev_sqlite_conn_open(_bytes(str(path)))
        if not self._handle:
            raise VevError("failed to open SQLite-backed Vev connection")
        if not library.lib.vev_sqlite_conn_ok(self._handle):
            error = library.owned_text(library.lib.vev_sqlite_conn_error(self._handle))
            self.close()
            raise VevError(error)

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_sqlite_conn_close(self._handle)
            self._handle = None

    def __enter__(self) -> "SQLiteConnection":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def transact(self, tx_edn: str) -> str:
        with self.transact_report(tx_edn) as report:
            return report.edn()

    def transact_report(self, tx_edn: str) -> "TxReport":
        self._require_open()
        handle = self._library.lib.vev_sqlite_conn_transact_edn_report(
            self._handle, _bytes(tx_edn)
        )
        if not handle:
            raise VevError("failed to transact")
        return TxReport(self._library, handle)

    def transact_bulk(self, txs: list["TxBuilder"] | tuple["TxBuilder", ...]) -> "TxReport":
        self._require_open()
        handles = _tx_builder_handle_array(txs)
        handle = self._library.lib.vev_sqlite_conn_tx_commit_many_report(
            self._handle, handles, len(txs)
        )
        if not handle:
            raise VevError("failed to transact bulk tx builders")
        return TxReport(self._library, handle)

    def transact_logical_bulk(
        self, txs: list["TxBuilder"] | tuple["TxBuilder", ...]
    ) -> "TxReportArray":
        self._require_open()
        handles = _tx_builder_handle_array(
            txs, name="transact_logical_bulk", allow_empty=True
        )
        handle = self._library.lib.vev_sqlite_conn_tx_commit_logical_many_reports(
            self._handle, handles, len(txs)
        )
        if not handle:
            raise VevError("failed to logical-group transact tx builders")
        return TxReportArray(self._library, handle)

    def transact_logical(
        self, txs: list[str] | tuple[str, ...]
    ) -> "TxReportArray":
        self._require_open()
        texts = _edn_text_array(txs, name="transact_logical")
        handle = self._library.lib.vev_sqlite_conn_transact_many_edn_reports(
            self._handle, texts, len(txs)
        )
        if not handle:
            raise VevError("failed to logical-group transact EDN tx data")
        return TxReportArray(self._library, handle)

    def db(self) -> "DB":
        self._require_open()
        handle = self._library.lib.vev_sqlite_conn_db(self._handle)
        if not handle:
            raise VevError("failed to retain DB snapshot")
        return DB(self._library, handle)

    def prepare(
        self, query_edn: str, source_names: list[str] | None = None
    ) -> "PreparedQuery":
        return PreparedQuery(self._library, query_edn, source_names)

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("SQLite-backed connection is closed")


class DB:
    def __init__(self, library: Library, handle: int):
        self._library = library
        self._handle = handle

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_db_release(self._handle)
            self._handle = None

    def __enter__(self) -> "DB":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def query(self, prepared: "PreparedQuery", inputs_edn: str = "[]") -> "Result":
        self._require_open()
        handle = self._library.lib.vev_query_db_prepared_result_with_inputs(
            self._handle, prepared._handle, _bytes(inputs_edn)
        )
        return Result(self._library, handle)

    def q(self, query_edn: str, inputs_edn: str = "[]") -> Any:
        """Run a query and return the value specified by its Datomic find shape."""
        self._require_open()
        handle = self._library.lib.vev_db_query_value_with_inputs(
            self._handle,
            _bytes(query_edn),
            _bytes(inputs_edn),
        )
        with ValueHandle(self._library, handle) as value:
            return value.value()

    def query_with_rules(
        self, prepared: "PreparedQuery", rules_edn: str, inputs_edn: str = "[]"
    ) -> "Result":
        self._require_open()
        handle = (
            self._library.lib.vev_query_db_prepared_result_with_rules_text_and_inputs(
                self._handle, prepared._handle, _bytes(rules_edn), _bytes(inputs_edn)
            )
        )
        return Result(self._library, handle)

    def query_columns(
        self, prepared: "PreparedQuery", inputs_edn: str = "[]"
    ) -> "ColumnResult | None":
        self._require_open()
        prepared._require_open()
        handle = self._library.lib.vev_query_db_prepared_column_batch_with_inputs(
            self._handle, prepared._handle, _bytes(inputs_edn)
        )
        return self._library._column_result_from_handle(handle)

    def query_stmt(self, stmt: "Statement") -> "Result":
        self._require_open()
        stmt._require_open()
        handle = self._library.lib.vev_query_db_stmt_result(self._handle, stmt._handle)
        return Result(self._library, handle)

    def query_stmt_columns(self, stmt: "Statement") -> "ColumnResult | None":
        self._require_open()
        stmt._require_open()
        handle = self._library.lib.vev_query_db_stmt_column_batch(
            self._handle, stmt._handle
        )
        return self._library._column_result_from_handle(handle)

    def with_text(self, tx_edn: str) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_with_edn(self._handle, _bytes(tx_edn))
        )

    def with_report(self, tx_edn: str) -> "TxReport":
        self._require_open()
        handle = self._library.lib.vev_with_edn_report(self._handle, _bytes(tx_edn))
        if not handle:
            raise VevError("failed to transact against DB snapshot")
        return TxReport(self._library, handle)

    def db_with(self, tx_edn: str) -> "DB":
        self._require_open()
        handle = self._library.lib.vev_db_with_edn(self._handle, _bytes(tx_edn))
        if not handle:
            raise VevError("failed to create DB snapshot")
        return DB(self._library, handle)

    def entity(self, entity: int | Entity) -> "EntityView":
        self._require_open()
        entity_id = entity.id if isinstance(entity, Entity) else int(entity)
        handle = self._library.lib.vev_db_entity(self._handle, entity_id)
        if not handle:
            raise VevError("failed to create entity view")
        return EntityView(self._library, handle)

    def entity_lookup_ref(self, attr: str, value: str) -> "EntityView":
        self._require_open()
        handle = self._library.lib.vev_db_entity_lookup_ref_string(
            self._handle, _bytes(attr), _bytes(value)
        )
        if not handle:
            raise VevError("failed to create lookup-ref entity view")
        return EntityView(self._library, handle)

    def entity_ident(self, ident: str) -> "EntityView":
        self._require_open()
        handle = self._library.lib.vev_db_entity_ident(self._handle, _bytes(ident))
        if not handle:
            raise VevError("failed to create ident entity view")
        return EntityView(self._library, handle)

    def pull(self, pattern_edn: str | "PreparedPullPattern", entity: int | Entity) -> Any:
        self._require_open()
        entity_id = entity.id if isinstance(entity, Entity) else int(entity)
        if isinstance(pattern_edn, PreparedPullPattern):
            pattern_edn._require_open()
            handle = self._library.lib.vev_pull_prepared(
                self._handle, pattern_edn._handle, entity_id
            )
        else:
            handle = self._library.lib.vev_pull_edn(
                self._handle, _bytes(pattern_edn), entity_id
            )
        with ValueHandle(self._library, handle) as value:
            return value.value()

    def pull_lookup_ref(self, pattern_edn: str, ref: LookupRef) -> Any:
        self._require_open()
        if not isinstance(ref.value, str):
            raise TypeError("pull_lookup_ref currently supports string lookup values")
        handle = self._library.lib.vev_pull_lookup_ref_string_edn(
            self._handle, _bytes(pattern_edn), _bytes(ref.attr), _bytes(ref.value)
        )
        with ValueHandle(self._library, handle) as value:
            return value.value()

    def pull_many(
        self, pattern_edn: str | "PreparedPullPattern", entities: list[int | Entity]
    ) -> list[Any]:
        self._require_open()
        ids = [entity.id if isinstance(entity, Entity) else int(entity) for entity in entities]
        array_type = ctypes.c_ulonglong * len(ids)
        array = array_type(*ids)
        if isinstance(pattern_edn, PreparedPullPattern):
            pattern_edn._require_open()
            handle = self._library.lib.vev_pull_many_prepared(
                self._handle, pattern_edn._handle, array, len(ids)
            )
        else:
            handle = self._library.lib.vev_pull_many_edn(
                self._handle, _bytes(pattern_edn), array, len(ids)
            )
        with ValueHandle(self._library, handle) as value:
            result = value.value()
        if not isinstance(result, list):
            raise VevError(f"expected pull_many vector, got {result!r}")
        return result

    def pull_many_lookup_ref(
        self, pattern_edn: str | "PreparedPullPattern", refs: list[LookupRef]
    ) -> list[Any]:
        self._require_open()
        if not refs:
            return []
        attr = refs[0].attr
        values: list[str] = []
        for ref in refs:
            if ref.attr != attr:
                raise TypeError("pull_many_lookup_ref requires one lookup-ref attr")
            if not isinstance(ref.value, str):
                raise TypeError("pull_many_lookup_ref currently supports string lookup values")
            values.append(ref.value)
        encoded_values = [_bytes(value) for value in values]
        array_type = ctypes.c_char_p * len(encoded_values)
        array = array_type(*encoded_values)
        if isinstance(pattern_edn, PreparedPullPattern):
            pattern_edn._require_open()
            handle = self._library.lib.vev_pull_many_lookup_ref_string_prepared(
                self._handle, pattern_edn._handle, _bytes(attr), array, len(encoded_values)
            )
        else:
            handle = self._library.lib.vev_pull_many_lookup_ref_string_edn(
                self._handle, _bytes(pattern_edn), _bytes(attr), array, len(encoded_values)
            )
        with ValueHandle(self._library, handle) as value:
            result = value.value()
        if not isinstance(result, list):
            raise VevError(f"expected pull_many_lookup_ref vector, got {result!r}")
        return result

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("DB snapshot is closed")


class EntityView:
    def __init__(self, library: Library, handle: int):
        self._library = library
        self._handle = handle
        if not self._handle:
            raise VevError("entity view is null")

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_entity_free(self._handle)
            self._handle = None

    def __enter__(self) -> "EntityView":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def __contains__(self, attr: str) -> bool:
        return self.contains(attr)

    def __getitem__(self, attr: str) -> Any:
        value = self.get(attr)
        if value is None:
            raise KeyError(attr)
        return value

    def found(self) -> bool:
        self._require_open()
        return bool(self._library.lib.vev_entity_found(self._handle))

    @property
    def id(self) -> int:
        self._require_open()
        return int(self._library.lib.vev_entity_id(self._handle))

    def contains(self, attr: str) -> bool:
        self._require_open()
        return bool(self._library.lib.vev_entity_contains(self._handle, _bytes(attr)))

    def get(self, attr: str, default: Any = None) -> Any:
        self._require_open()
        handle = self._library.lib.vev_entity_get(self._handle, _bytes(attr))
        with ValueHandle(self._library, handle) as value:
            result = value.value()
        return default if result is None else result

    def values(self, attr: str) -> list[Any]:
        self._require_open()
        handle = self._library.lib.vev_entity_values(self._handle, _bytes(attr))
        with ValueHandle(self._library, handle) as value:
            result = value.value()
        if not isinstance(result, list):
            raise VevError(f"expected entity values vector, got {result!r}")
        return result

    def ref(self, attr: str) -> "EntityView":
        self._require_open()
        handle = self._library.lib.vev_entity_ref(self._handle, _bytes(attr))
        if not handle:
            raise VevError("failed to create referenced entity view")
        return EntityView(self._library, handle)

    def refs(self, attr: str) -> list[Entity]:
        self._require_open()
        handle = self._library.lib.vev_entity_refs(self._handle, _bytes(attr))
        if not handle:
            return []
        try:
            count = int(self._library.lib.vev_u64_array_count(handle))
            return [
                Entity(int(self._library.lib.vev_u64_array_value(handle, index)))
                for index in range(count)
            ]
        finally:
            self._library.lib.vev_u64_array_free(handle)

    def touch(self) -> Any:
        self._require_open()
        handle = self._library.lib.vev_entity_touch(self._handle)
        with ValueHandle(self._library, handle) as value:
            return value.value()

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("entity view is closed")


class ValueHandle:
    def __init__(self, library: Library, handle: int):
        self._library = library
        self._handle = handle
        if not self._handle:
            raise VevError("value handle is null")

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_value_handle_free(self._handle)
            self._handle = None

    def __enter__(self) -> "ValueHandle":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def value(self) -> Any:
        self._require_open()
        return self._library.value_to_python(
            self._library.lib.vev_value_handle_value(self._handle)
        )

    def edn(self) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_value_handle_edn(self._handle)
        )

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("value handle is closed")


class TxReport:
    def __init__(self, library: Library, handle: int, owned: bool = True):
        self._library = library
        self._handle = handle
        self._owned = owned

    def close(self) -> None:
        if self._handle:
            if self._owned:
                self._library.lib.vev_tx_report_free(self._handle)
            self._handle = None

    def __enter__(self) -> "TxReport":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def value(self) -> Any:
        self._require_open()
        return self._library.value_to_python(
            self._library.lib.vev_tx_report_value(self._handle)
        )

    def edn(self) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_tx_report_edn(self._handle)
        )

    def db_before(self) -> DB:
        self._require_open()
        handle = self._library.lib.vev_tx_report_db_before(self._handle)
        if not handle:
            raise VevError("transaction report has no db-before")
        return DB(self._library, handle)

    def db_after(self) -> DB:
        self._require_open()
        handle = self._library.lib.vev_tx_report_db_after(self._handle)
        if not handle:
            raise VevError("transaction report has no db-after")
        return DB(self._library, handle)

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("transaction report is closed")


class TxReportArray:
    def __init__(self, library: Library, handle: int):
        self._library = library
        self._handle = handle

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_tx_report_array_free(self._handle)
            self._handle = None

    def __enter__(self) -> "TxReportArray":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def __len__(self) -> int:
        self._require_open()
        return int(self._library.lib.vev_tx_report_array_count(self._handle))

    def get(self, index: int) -> TxReport:
        self._require_open()
        handle = self._library.lib.vev_tx_report_array_get(self._handle, int(index))
        if not handle:
            raise VevError("transaction report index out of range")
        return TxReport(self._library, handle, owned=False)

    def values(self) -> list[Any]:
        return [self.get(index).value() for index in range(len(self))]

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("transaction report array is closed")


class TxBuilder:
    def __init__(self, library: Library | None = None, capacity: int = 0):
        self._library = library if library is not None else default_library()
        self._handle = self._library.lib.vev_tx_create(capacity)
        if not self._handle:
            raise VevError("failed to create transaction builder")

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_tx_free(self._handle)
            self._handle = None

    def __enter__(self) -> "TxBuilder":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def add_string(self, entity: int, attr: str, value: str) -> "TxBuilder":
        self._add(
            self._library.lib.vev_tx_add_string,
            entity,
            attr,
            _bytes(value),
            "string",
        )
        return self

    def add_keyword(self, entity: int, attr: str, value: str) -> "TxBuilder":
        self._add(
            self._library.lib.vev_tx_add_keyword,
            entity,
            attr,
            _bytes(value),
            "keyword",
        )
        return self

    def add_symbol(self, entity: int, attr: str, value: str) -> "TxBuilder":
        self._add(
            self._library.lib.vev_tx_add_symbol,
            entity,
            attr,
            _bytes(value),
            "symbol",
        )
        return self

    def add_entity(self, entity: int, attr: str, value: int) -> "TxBuilder":
        self._add(
            self._library.lib.vev_tx_add_entity,
            entity,
            attr,
            int(value),
            "entity",
        )
        return self

    def add_int(self, entity: int, attr: str, value: int) -> "TxBuilder":
        self._add(self._library.lib.vev_tx_add_int, entity, attr, int(value), "int")
        return self

    def add_bool(self, entity: int, attr: str, value: bool) -> "TxBuilder":
        self._add(
            self._library.lib.vev_tx_add_bool,
            entity,
            attr,
            bool(value),
            "bool",
        )
        return self

    def _add(
        self,
        add_fn: object,
        entity: int,
        attr: str,
        value: object,
        value_type: str,
    ) -> None:
        self._require_open()
        if not add_fn(self._handle, entity, _bytes(attr), value):
            raise VevError(f"failed to add {value_type} datom to transaction builder")

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("transaction builder is closed")


def _tx_builder_handle_array(
    txs: list[TxBuilder] | tuple[TxBuilder, ...],
    name: str = "transact_bulk",
    allow_empty: bool = False,
) -> object:
    if len(txs) == 0:
        if allow_empty:
            return None
        raise VevError(f"{name} requires at least one transaction builder")
    array = (ctypes.c_void_p * len(txs))()
    for index, tx in enumerate(txs):
        if not isinstance(tx, TxBuilder):
            raise VevError(f"{name} expects TxBuilder values")
        tx._require_open()
        array[index] = tx._handle
    return array


def _edn_text_array(
    txs: list[str] | tuple[str, ...],
    name: str = "transact_logical",
) -> object:
    if len(txs) == 0:
        return None
    encoded = []
    for tx in txs:
        if not isinstance(tx, str):
            raise VevError(f"{name} expects EDN transaction strings")
        encoded.append(_bytes(tx))
    array_type = ctypes.c_char_p * len(encoded)
    return array_type(*encoded)


class PreparedQuery:
    def __init__(
        self,
        library: Library,
        query_edn: str,
        source_names: list[str] | None = None,
    ):
        self._library = library
        if source_names is None:
            self._handle = library.lib.vev_prepare_query_edn(_bytes(query_edn))
        else:
            encoded = [_bytes(name) for name in source_names]
            array_type = ctypes.c_char_p * len(encoded)
            array = array_type(*encoded)
            self._handle = library.lib.vev_prepare_query_edn_with_sources(
                _bytes(query_edn), array, len(encoded)
            )
        if not self._handle:
            raise VevError("failed to prepare query")
        if not library.lib.vev_prepared_query_ok(self._handle):
            try:
                error = library.owned_text(
                    library.lib.vev_prepared_query_error(self._handle)
                )
            finally:
                library.lib.vev_prepared_query_free(self._handle)
                self._handle = None
            raise VevError(error)

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_prepared_query_free(self._handle)
            self._handle = None

    def __enter__(self) -> "PreparedQuery":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def statement(self) -> "Statement":
        self._require_open()
        return Statement(self._library, self)

    def edn(self) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_prepared_query_edn(self._handle)
        )

    def query(self, conn: Connection | DB, inputs_edn: str = "[]") -> "Result":
        self._require_open()
        if isinstance(conn, Connection):
            return conn._query_result(self, inputs_edn)
        return conn.query(self, inputs_edn)

    def query_with_rules(
        self, conn: Connection | DB, rules_edn: str, inputs_edn: str = "[]"
    ) -> "Result":
        self._require_open()
        if isinstance(conn, Connection):
            return conn._query_result_with_rules(self, rules_edn, inputs_edn)
        return conn.query_with_rules(self, rules_edn, inputs_edn)

    def rows(self, conn: Connection | DB, inputs_edn: str = "[]") -> list[list[Any]]:
        with self.query(conn, inputs_edn) as result:
            return result.rows()

    def rows_with_rules(
        self, conn: Connection | DB, rules_edn: str, inputs_edn: str = "[]"
    ) -> list[list[Any]]:
        with self.query_with_rules(conn, rules_edn, inputs_edn) as result:
            return result.rows()

    def scalar(self, conn: Connection | DB, inputs_edn: str = "[]") -> Any:
        with self.query(conn, inputs_edn) as result:
            return result.scalar()

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("prepared query is closed")


class PreparedPullPattern:
    def __init__(self, library: Library, pattern_edn: str):
        self._library = library
        self._handle = library.lib.vev_prepare_pull_pattern_edn(_bytes(pattern_edn))
        if not self._handle:
            raise VevError("failed to prepare pull pattern")
        if not library.lib.vev_prepared_pull_pattern_ok(self._handle):
            try:
                error = library.owned_text(
                    library.lib.vev_prepared_pull_pattern_error(self._handle)
                )
            finally:
                library.lib.vev_prepared_pull_pattern_free(self._handle)
                self._handle = None
            raise VevError(error)

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_prepared_pull_pattern_free(self._handle)
            self._handle = None

    def __enter__(self) -> "PreparedPullPattern":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def edn(self) -> str:
        self._require_open()
        return self._library.owned_text(
            self._library.lib.vev_prepared_pull_pattern_edn(self._handle)
        )

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("prepared pull pattern is closed")


class Statement:
    def __init__(self, library: Library, prepared: PreparedQuery):
        self._library = library
        self._prepared = prepared
        self._handle = library.lib.vev_stmt_create(prepared._handle)
        if not self._handle:
            raise VevError("failed to create statement")

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_stmt_free(self._handle)
            self._handle = None

    def __enter__(self) -> "Statement":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def clear(self) -> None:
        self._require_open()
        self._library.lib.vev_stmt_clear(self._handle)

    def bind(self, *values: object) -> "Statement":
        self.clear()
        for value in values:
            self._bind_one(value)
        return self

    def query(self, conn: Connection | DB) -> "Result":
        self._require_open()
        if isinstance(conn, Connection):
            return conn._query_stmt(self)
        return conn.query_stmt(self)

    def rows(self, conn: Connection | DB) -> list[list[Any]]:
        with self.query(conn) as result:
            return result.rows()

    def scalar(self, conn: Connection | DB) -> Any:
        with self.query(conn) as result:
            return result.scalar()

    def columns(self, conn: Connection | DB) -> "ColumnResult | None":
        self._require_open()
        if isinstance(conn, Connection):
            return conn._query_stmt_columns(self)
        return conn.query_stmt_columns(self)

    def error(self) -> str:
        self._require_open()
        return self._library.owned_text(self._library.lib.vev_stmt_error(self._handle))

    def visit(self, conn: Connection | DB, visitor: object) -> None:
        self._require_open()
        if isinstance(conn, Connection):
            conn._require_open()
            fn = self._library.lib.vev_query_stmt_visit
            owner = conn._handle
        else:
            conn._require_open()
            fn = self._library.lib.vev_query_db_stmt_visit
            owner = conn._handle

        def callback(
            _user: int, event: int, row: int, index: int, value: int
        ) -> bool:
            converted = (
                self._library.value_to_python(value)
                if event in (VEV_RESULT_VISIT_VALUE, VEV_RESULT_VISIT_PULL)
                else None
            )
            return bool(visitor(event, row, index, converted))

        c_callback = RESULT_VISIT_FN(callback)
        if not fn(owner, self._handle, c_callback, None):
            raise VevError(self.error() or "statement visitor failed")

    def stream_rows(self, conn: Connection | DB) -> list[list[Any]]:
        rows: list[list[Any]] = []
        current: list[Any] = []

        def collect(event: int, row: int, index: int, value: Any) -> bool:
            nonlocal current
            if event == VEV_RESULT_VISIT_ROW_BEGIN:
                current = []
            elif event in (VEV_RESULT_VISIT_VALUE, VEV_RESULT_VISIT_PULL):
                current.append(value)
            elif event == VEV_RESULT_VISIT_ROW_END:
                rows.append(current)
            return True

        self.visit(conn, collect)
        return rows

    def _bind_one(self, value: object) -> None:
        lib = self._library.lib
        if isinstance(value, Entity):
            ok = lib.vev_stmt_bind_entity(self._handle, value.id)
        elif isinstance(value, LookupRef):
            ok = self._bind_lookup_ref(value)
        elif isinstance(value, TypedTuple):
            ok = self._bind_homogeneous_values(value.values, "tuple", value_type=value.value_type)
        elif isinstance(value, TupleInput):
            ok = self._bind_tuple(value.values)
        elif isinstance(value, TypedRelation):
            ok = self._bind_typed_relation(value)
        elif isinstance(value, Relation):
            ok = self._bind_relation(value.rows)
        elif isinstance(value, TypedCollection):
            ok = self._bind_homogeneous_values(
                value.values, "collection", value_type=value.value_type
            )
        elif isinstance(value, PullPattern):
            ok = lib.vev_stmt_bind_pull_pattern_edn(self._handle, _bytes(value.edn))
        elif isinstance(value, DBSource):
            value.db._require_open()
            ok = lib.vev_stmt_bind_db_source(
                self._handle, _bytes(value.name), value.db._handle
            )
        elif isinstance(value, bool):
            ok = lib.vev_stmt_bind_bool(self._handle, value)
        elif isinstance(value, int):
            ok = lib.vev_stmt_bind_int(self._handle, value)
        elif isinstance(value, Keyword):
            ok = lib.vev_stmt_bind_keyword(self._handle, _bytes(value.text))
        elif isinstance(value, Symbol):
            ok = lib.vev_stmt_bind_symbol(self._handle, _bytes(value.text))
        elif isinstance(value, str):
            ok = lib.vev_stmt_bind_string(self._handle, _bytes(value))
        elif isinstance(value, (list, tuple)):
            ok = self._bind_collection(value)
        else:
            raise TypeError(f"unsupported Vev statement binding: {value!r}")
        if not ok:
            raise VevError(f"failed to bind statement value: {value!r}")

    def _bind_lookup_ref(self, ref: LookupRef) -> bool:
        lib = self._library.lib
        attr = _bytes(ref.attr)
        value = ref.value
        if isinstance(value, Entity):
            return bool(lib.vev_stmt_bind_lookup_ref_entity(self._handle, attr, value.id))
        if isinstance(value, int) and not isinstance(value, bool):
            return bool(lib.vev_stmt_bind_lookup_ref_int(self._handle, attr, value))
        if isinstance(value, Keyword):
            return bool(
                lib.vev_stmt_bind_lookup_ref_keyword(self._handle, attr, _bytes(value.text))
            )
        if isinstance(value, str):
            return bool(lib.vev_stmt_bind_lookup_ref_string(self._handle, attr, _bytes(value)))
        raise TypeError(f"unsupported Vev lookup-ref binding: {ref!r}")

    def _bind_tuple(self, values: tuple[object, ...]) -> bool:
        return self._bind_homogeneous_values(values, "tuple")

    def _bind_typed_relation(self, relation: TypedRelation) -> bool:
        if relation.width <= 0:
            raise TypeError(f"typed relation width must be positive: {relation!r}")
        if len(relation.rows) == 0:
            return self._bind_homogeneous_values(
                (), "relation", relation.width, value_type=relation.value_type
            )
        if any(len(row) != relation.width for row in relation.rows):
            raise TypeError(f"relation rows must match declared width: {relation!r}")
        flat = tuple(value for row in relation.rows for value in row)
        return self._bind_homogeneous_values(
            flat, "relation", relation.width, value_type=relation.value_type
        )

    def _bind_relation(self, rows: tuple[tuple[object, ...], ...]) -> bool:
        if len(rows) == 0:
            raise TypeError("empty relation bindings need an explicit typed wrapper")
        width = len(rows[0])
        if width == 0 or any(len(row) != width for row in rows):
            raise TypeError(f"relation rows must have a stable non-zero width: {rows!r}")
        flat = tuple(value for row in rows for value in row)
        return self._bind_homogeneous_values(flat, "relation", width)

    def _bind_homogeneous_values(
        self,
        values: tuple[object, ...],
        kind: str,
        width: int | None = None,
        value_type: str | None = None,
    ) -> bool:
        lib = self._library.lib
        suffix = "_relation" if kind == "relation" else f"_{kind}"
        if len(values) == 0:
            if value_type is None:
                raise TypeError(f"empty {kind} bindings need an explicit typed wrapper")
            if value_type == "entity":
                fn = getattr(lib, f"vev_stmt_bind_entity{suffix}")
            elif value_type == "bool":
                fn = getattr(lib, f"vev_stmt_bind_bool{suffix}")
            elif value_type == "int":
                fn = getattr(lib, f"vev_stmt_bind_int{suffix}")
            elif value_type == "string":
                fn = getattr(lib, f"vev_stmt_bind_string{suffix}")
            else:
                raise TypeError(f"unsupported typed {kind} value type: {value_type!r}")
            if kind == "relation":
                assert width is not None
                return bool(fn(self._handle, None, 0, width))
            return bool(fn(self._handle, None, 0))
        if value_type is not None and not all(_value_matches_type(value, value_type) for value in values):
            raise TypeError(f"typed {kind} contains values outside {value_type!r}: {values!r}")
        if all(isinstance(value, Entity) for value in values):
            array_type = ctypes.c_ulonglong * len(values)
            array = array_type(*(value.id for value in values))
            fn = getattr(lib, f"vev_stmt_bind_entity{suffix}")
        elif all(isinstance(value, bool) for value in values):
            array_type = ctypes.c_bool * len(values)
            array = array_type(*values)
            fn = getattr(lib, f"vev_stmt_bind_bool{suffix}")
        elif all(isinstance(value, int) and not isinstance(value, bool) for value in values):
            array_type = ctypes.c_longlong * len(values)
            array = array_type(*values)
            fn = getattr(lib, f"vev_stmt_bind_int{suffix}")
        elif all(isinstance(value, str) for value in values):
            encoded = [_bytes(value) for value in values]
            array_type = ctypes.c_char_p * len(encoded)
            array = array_type(*encoded)
            fn = getattr(lib, f"vev_stmt_bind_string{suffix}")
        else:
            raise TypeError(f"unsupported homogeneous {kind} binding: {values!r}")
        if kind == "relation":
            assert width is not None
            return bool(fn(self._handle, array, len(values), width))
        return bool(fn(self._handle, array, len(values)))

    def _bind_collection(self, values: list[object] | tuple[object, ...]) -> bool:
        lib = self._library.lib
        if len(values) == 0:
            raise TypeError("empty collection bindings need an explicit typed wrapper")
        if all(isinstance(value, LookupRef) for value in values):
            attrs = {value.attr for value in values}
            if len(attrs) != 1:
                raise TypeError("lookup-ref collection bindings require one attr")
            lookup_values = tuple(value.value for value in values)
            attr = _bytes(values[0].attr)
            if all(isinstance(value, Entity) for value in lookup_values):
                array_type = ctypes.c_ulonglong * len(lookup_values)
                array = array_type(*(value.id for value in lookup_values))
                return bool(
                    lib.vev_stmt_bind_lookup_ref_entity_collection(
                        self._handle, attr, array, len(lookup_values)
                    )
                )
            if all(isinstance(value, int) and not isinstance(value, bool) for value in lookup_values):
                array_type = ctypes.c_longlong * len(lookup_values)
                array = array_type(*lookup_values)
                return bool(
                    lib.vev_stmt_bind_lookup_ref_int_collection(
                        self._handle, attr, array, len(lookup_values)
                    )
                )
            if all(isinstance(value, Keyword) for value in lookup_values):
                encoded = [_bytes(value.text) for value in lookup_values]
                array_type = ctypes.c_char_p * len(encoded)
                array = array_type(*encoded)
                return bool(
                    lib.vev_stmt_bind_lookup_ref_keyword_collection(
                        self._handle, attr, array, len(encoded)
                    )
                )
            if all(isinstance(value, str) for value in lookup_values):
                encoded = [_bytes(value) for value in lookup_values]
                array_type = ctypes.c_char_p * len(encoded)
                array = array_type(*encoded)
                return bool(
                    lib.vev_stmt_bind_lookup_ref_string_collection(
                        self._handle, attr, array, len(encoded)
                    )
                )
            raise TypeError(f"unsupported lookup-ref collection binding: {values!r}")
        if all(isinstance(value, Entity) for value in values):
            array_type = ctypes.c_ulonglong * len(values)
            array = array_type(*(value.id for value in values))
            return bool(lib.vev_stmt_bind_entity_collection(self._handle, array, len(values)))
        if all(isinstance(value, bool) for value in values):
            array_type = ctypes.c_bool * len(values)
            array = array_type(*values)
            return bool(lib.vev_stmt_bind_bool_collection(self._handle, array, len(values)))
        if all(isinstance(value, int) and not isinstance(value, bool) for value in values):
            array_type = ctypes.c_longlong * len(values)
            array = array_type(*values)
            return bool(lib.vev_stmt_bind_int_collection(self._handle, array, len(values)))
        if all(isinstance(value, str) for value in values):
            encoded = [_bytes(value) for value in values]
            array_type = ctypes.c_char_p * len(encoded)
            array = array_type(*encoded)
            return bool(lib.vev_stmt_bind_string_collection(self._handle, array, len(encoded)))
        raise TypeError(f"unsupported Vev collection binding: {values!r}")

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("statement is closed")


@dataclass(frozen=True)
class Keyword:
    text: str


@dataclass(frozen=True)
class Symbol:
    text: str


class Result:
    def __init__(self, library: Library, handle: int):
        self._library = library
        self._handle = handle
        if not self._handle:
            raise VevError("query returned a null result")
        if not library.lib.vev_result_ok(self._handle):
            try:
                error = library.owned_text(library.lib.vev_result_error(self._handle))
            finally:
                library.lib.vev_result_free(self._handle)
                self._handle = None
            raise VevError(error)

    def close(self) -> None:
        if self._handle:
            self._library.lib.vev_result_free(self._handle)
            self._handle = None

    def __enter__(self) -> "Result":
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

    def rows(self) -> list[list[Any]]:
        self._require_open()
        out = []
        for row in range(self._library.lib.vev_result_row_count(self._handle)):
            values = [
                self._library.value_to_python(
                    self._library.lib.vev_result_value(self._handle, row, column)
                )
                for column in range(self._library.lib.vev_result_value_count(self._handle, row))
            ]
            values.extend(self.pulls(row))
            out.append(values)
        return out

    def pulls(self, row: int) -> list[Any]:
        self._require_open()
        return [
            self._library.value_to_python(
                self._library.lib.vev_result_pull(self._handle, row, index)
            )
            for index in range(self._library.lib.vev_result_pull_count(self._handle, row))
        ]

    def scalar(self) -> Any:
        rows = self.rows()
        if len(rows) != 1 or len(rows[0]) != 1:
            raise VevError(f"expected one scalar result, got {rows!r}")
        return rows[0][0]

    def _require_open(self) -> None:
        if not self._handle:
            raise VevError("result is closed")


@dataclass(frozen=True)
class ColumnResult:
    count: int
    kinds: tuple[int, ...]
    columns: tuple[list[object], ...]

    def rows(self) -> list[list[object]]:
        return [[column[row] for column in self.columns] for row in range(self.count)]
