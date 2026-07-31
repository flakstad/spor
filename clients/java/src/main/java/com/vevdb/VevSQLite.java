// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package com.vevdb;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;

/**
 * Direct access to the SQLite implementation bundled in VevDB.
 *
 * <p>Application SQLite databases must use files separate from Vev fact
 * stores. The native API rejects Vev fact-store files.</p>
 */
public final class VevSQLite implements AutoCloseable {
    private static final Linker LINKER = Linker.nativeLinker();

    public static final int OK = 0;
    public static final int ERROR = 1;
    public static final int BUSY = 5;
    public static final int LOCKED = 6;
    public static final int READONLY = 8;
    public static final int INTERRUPT = 9;
    public static final int CANTOPEN = 14;
    public static final int CONSTRAINT = 19;
    public static final int MISUSE = 21;
    public static final int AUTH = 23;
    public static final int RANGE = 25;
    public static final int ROW = 100;
    public static final int DONE = 101;

    public static final int INTEGER = 1;
    public static final int FLOAT = 2;
    public static final int TEXT = 3;
    public static final int BLOB = 4;
    public static final int NULL = 5;

    public static final int OPEN_READONLY = 0x00000001;
    public static final int OPEN_READWRITE = 0x00000002;
    public static final int OPEN_CREATE = 0x00000004;
    public static final int OPEN_URI = 0x00000040;
    public static final int OPEN_MEMORY = 0x00000080;
    public static final int OPEN_NOMUTEX = 0x00008000;
    public static final int OPEN_FULLMUTEX = 0x00010000;

    private final Arena arena;
    private final SymbolLookup symbols;
    private boolean closed;

    private final MethodHandle stringFree;
    private final MethodHandle open;
    private final MethodHandle openV2;
    private final MethodHandle dbOk;
    private final MethodHandle dbErrorCode;
    private final MethodHandle dbExtendedErrorCode;
    private final MethodHandle dbError;
    private final MethodHandle dbClose;
    private final MethodHandle exec;
    private final MethodHandle prepare;
    private final MethodHandle stmtFinalize;
    private final MethodHandle stmtReset;
    private final MethodHandle stmtClearBindings;
    private final MethodHandle stmtStep;
    private final MethodHandle stmtReadonly;
    private final MethodHandle bindNull;
    private final MethodHandle bindInt64;
    private final MethodHandle bindDouble;
    private final MethodHandle bindText;
    private final MethodHandle bindBlob;
    private final MethodHandle bindParameterCount;
    private final MethodHandle bindParameterIndex;
    private final MethodHandle bindParameterName;
    private final MethodHandle columnCount;
    private final MethodHandle columnName;
    private final MethodHandle columnType;
    private final MethodHandle columnInt64;
    private final MethodHandle columnDouble;
    private final MethodHandle columnText;
    private final MethodHandle columnBlob;
    private final MethodHandle columnBytes;
    private final MethodHandle changes;
    private final MethodHandle totalChanges;
    private final MethodHandle lastInsertRowid;
    private final MethodHandle autocommit;
    private final MethodHandle busyTimeout;
    private final MethodHandle interrupt;
    private final MethodHandle version;
    private final MethodHandle sourceId;
    private final MethodHandle compileOptionUsed;

    public static VevSQLite load() {
        return new VevSQLite(Vev.defaultLibraryPath());
    }

    public static VevSQLite load(Path libraryPath) {
        return new VevSQLite(libraryPath);
    }

    public VevSQLite(Path libraryPath) {
        this.arena = Arena.ofShared();
        this.symbols = SymbolLookup.libraryLookup(libraryPath, arena);

        this.stringFree = downcall(
            "vev_string_free",
            FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.open = downcall(
            "vev_sqlite_open",
            FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.openV2 = downcall(
            "vev_sqlite_open_v2",
            FunctionDescriptor.of(
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.dbOk = downcall(
            "vev_sqlite_db_ok",
            FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.dbErrorCode = downcall(
            "vev_sqlite_db_error_code",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.dbExtendedErrorCode = downcall(
            "vev_sqlite_db_extended_error_code",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.dbError = downcall(
            "vev_sqlite_db_error",
            FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.dbClose = downcall(
            "vev_sqlite_db_close",
            FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.exec = downcall(
            "vev_sqlite_exec",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS));
        this.prepare = downcall(
            "vev_sqlite_prepare",
            FunctionDescriptor.of(
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS));
        this.stmtFinalize = downcall(
            "vev_sqlite_stmt_finalize",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.stmtReset = downcall(
            "vev_sqlite_stmt_reset",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.stmtClearBindings = downcall(
            "vev_sqlite_stmt_clear_bindings",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.stmtStep = downcall(
            "vev_sqlite_stmt_step",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.stmtReadonly = downcall(
            "vev_sqlite_stmt_readonly",
            FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.bindNull = downcall(
            "vev_sqlite_bind_null",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.bindInt64 = downcall(
            "vev_sqlite_bind_int64",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT,
                ValueLayout.JAVA_LONG));
        this.bindDouble = downcall(
            "vev_sqlite_bind_double",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT,
                ValueLayout.JAVA_DOUBLE));
        this.bindText = downcall(
            "vev_sqlite_bind_text",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_LONG));
        this.bindBlob = downcall(
            "vev_sqlite_bind_blob",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_LONG));
        this.bindParameterCount = downcall(
            "vev_sqlite_bind_parameter_count",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.bindParameterIndex = downcall(
            "vev_sqlite_bind_parameter_index",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS));
        this.bindParameterName = downcall(
            "vev_sqlite_bind_parameter_name",
            FunctionDescriptor.of(
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.columnCount = downcall(
            "vev_sqlite_column_count",
            FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.columnName = downcall(
            "vev_sqlite_column_name",
            FunctionDescriptor.of(
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.columnType = downcall(
            "vev_sqlite_column_type",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.columnInt64 = downcall(
            "vev_sqlite_column_int64",
            FunctionDescriptor.of(
                ValueLayout.JAVA_LONG,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.columnDouble = downcall(
            "vev_sqlite_column_double",
            FunctionDescriptor.of(
                ValueLayout.JAVA_DOUBLE,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.columnText = downcall(
            "vev_sqlite_column_text",
            FunctionDescriptor.of(
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.columnBlob = downcall(
            "vev_sqlite_column_blob",
            FunctionDescriptor.of(
                ValueLayout.ADDRESS,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.columnBytes = downcall(
            "vev_sqlite_column_bytes",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.changes = downcall(
            "vev_sqlite_changes",
            FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.totalChanges = downcall(
            "vev_sqlite_total_changes",
            FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.lastInsertRowid = downcall(
            "vev_sqlite_last_insert_rowid",
            FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.autocommit = downcall(
            "vev_sqlite_autocommit",
            FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.busyTimeout = downcall(
            "vev_sqlite_busy_timeout",
            FunctionDescriptor.of(
                ValueLayout.JAVA_INT,
                ValueLayout.ADDRESS,
                ValueLayout.JAVA_INT));
        this.interrupt = downcall(
            "vev_sqlite_interrupt",
            FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.version = downcall(
            "vev_sqlite_version",
            FunctionDescriptor.of(ValueLayout.ADDRESS));
        this.sourceId = downcall(
            "vev_sqlite_source_id",
            FunctionDescriptor.of(ValueLayout.ADDRESS));
        this.compileOptionUsed = downcall(
            "vev_sqlite_compile_option_used",
            FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
    }

    public Connection open(String path) throws Throwable {
        return open(Path.of(path));
    }

    public Connection open(Path path) throws Throwable {
        requireOpen();
        try (Arena local = Arena.ofConfined()) {
            return checkedConnection((MemorySegment) open.invoke(
                local.allocateFrom(path.toString())));
        }
    }

    public Connection open(String path, int flags) throws Throwable {
        return open(Path.of(path), flags);
    }

    public Connection open(Path path, int flags) throws Throwable {
        requireOpen();
        try (Arena local = Arena.ofConfined()) {
            return checkedConnection((MemorySegment) openV2.invoke(
                local.allocateFrom(path.toString()),
                flags));
        }
    }

    public String version() throws Throwable {
        requireOpen();
        return ownedString((MemorySegment) version.invoke());
    }

    public String sourceId() throws Throwable {
        requireOpen();
        return ownedString((MemorySegment) sourceId.invoke());
    }

    public boolean compileOptionUsed(String option) throws Throwable {
        requireOpen();
        try (Arena local = Arena.ofConfined()) {
            return (boolean) compileOptionUsed.invoke(local.allocateFrom(option));
        }
    }

    private Connection checkedConnection(MemorySegment raw) throws Throwable {
        if (isNull(raw)) {
            throw new IllegalStateException("SQLite open returned no handle");
        }
        if (!(boolean) dbOk.invoke(raw)) {
            int code = (int) dbErrorCode.invoke(raw);
            int extended = (int) dbExtendedErrorCode.invoke(raw);
            String message = ownedString((MemorySegment) dbError.invoke(raw));
            dbClose.invoke(raw);
            throw new SQLiteException(code, extended, message);
        }
        return new Connection(raw);
    }

    private MethodHandle downcall(String name, FunctionDescriptor descriptor) {
        MemorySegment symbol = symbols.find(name).orElseThrow(
            () -> new IllegalStateException("missing symbol: " + name));
        return LINKER.downcallHandle(symbol, descriptor);
    }

    private String ownedString(MemorySegment pointer) throws Throwable {
        if (isNull(pointer)) return "";
        String value = pointer.reinterpret(Long.MAX_VALUE).getString(0);
        stringFree.invoke(pointer);
        return value;
    }

    private static boolean isNull(MemorySegment value) {
        return value == null || value.address() == 0;
    }

    private void requireOpen() {
        if (closed) throw new IllegalStateException("SQLite library is closed");
    }

    @Override
    public void close() {
        if (!closed) {
            closed = true;
            arena.close();
        }
    }

    public static final class SQLiteException extends RuntimeException {
        private static final long serialVersionUID = 1L;
        private final int code;
        private final int extendedCode;

        public SQLiteException(int code, int extendedCode, String message) {
            super(message);
            this.code = code;
            this.extendedCode = extendedCode;
        }

        public int code() {
            return code;
        }

        public int extendedCode() {
            return extendedCode;
        }
    }

    public final class Connection implements AutoCloseable {
        private MemorySegment raw;

        private Connection(MemorySegment raw) {
            this.raw = raw;
        }

        public int exec(String sql) throws Throwable {
            requireConnectionOpen();
            try (Arena local = Arena.ofConfined()) {
                return (int) exec.invoke(raw, local.allocateFrom(sql));
            }
        }

        public Statement prepare(String sql) throws Throwable {
            requireConnectionOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment statement = (MemorySegment) prepare.invoke(
                    raw,
                    local.allocateFrom(sql));
                if (isNull(statement)) throw error();
                return new Statement(this, statement);
            }
        }

        public int errorCode() throws Throwable {
            requireConnectionOpen();
            return (int) dbErrorCode.invoke(raw);
        }

        public int extendedErrorCode() throws Throwable {
            requireConnectionOpen();
            return (int) dbExtendedErrorCode.invoke(raw);
        }

        public String errorMessage() throws Throwable {
            requireConnectionOpen();
            return ownedString((MemorySegment) dbError.invoke(raw));
        }

        public SQLiteException error() throws Throwable {
            return new SQLiteException(
                errorCode(),
                extendedErrorCode(),
                errorMessage());
        }

        public long changes() throws Throwable {
            requireConnectionOpen();
            return (long) changes.invoke(raw);
        }

        public long totalChanges() throws Throwable {
            requireConnectionOpen();
            return (long) totalChanges.invoke(raw);
        }

        public long lastInsertRowid() throws Throwable {
            requireConnectionOpen();
            return (long) lastInsertRowid.invoke(raw);
        }

        public boolean autocommit() throws Throwable {
            requireConnectionOpen();
            return (boolean) autocommit.invoke(raw);
        }

        public int busyTimeout(int milliseconds) throws Throwable {
            requireConnectionOpen();
            return (int) busyTimeout.invoke(raw, milliseconds);
        }

        public void interrupt() throws Throwable {
            requireConnectionOpen();
            interrupt.invoke(raw);
        }

        private void requireConnectionOpen() {
            requireOpen();
            if (isNull(raw)) throw new IllegalStateException("SQLite connection is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                try {
                    dbClose.invoke(raw);
                } catch (Throwable error) {
                    throw new IllegalStateException("failed to close SQLite connection", error);
                } finally {
                    raw = MemorySegment.NULL;
                }
            }
        }
    }

    public final class Statement implements AutoCloseable {
        private final Connection connection;
        private MemorySegment raw;

        private Statement(Connection connection, MemorySegment raw) {
            this.connection = connection;
            this.raw = raw;
        }

        public int parameterCount() throws Throwable {
            requireStatementOpen();
            return (int) bindParameterCount.invoke(raw);
        }

        public int parameterIndex(String name) throws Throwable {
            requireStatementOpen();
            try (Arena local = Arena.ofConfined()) {
                return (int) bindParameterIndex.invoke(raw, local.allocateFrom(name));
            }
        }

        public String parameterName(int index) throws Throwable {
            requireStatementOpen();
            return ownedString((MemorySegment) bindParameterName.invoke(raw, index));
        }

        public int bindNull(int index) throws Throwable {
            requireStatementOpen();
            return (int) bindNull.invoke(raw, index);
        }

        public int bindLong(int index, long value) throws Throwable {
            requireStatementOpen();
            return (int) bindInt64.invoke(raw, index, value);
        }

        public int bindDouble(int index, double value) throws Throwable {
            requireStatementOpen();
            return (int) bindDouble.invoke(raw, index, value);
        }

        public int bindString(int index, String value) throws Throwable {
            byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
            return bindBytes(bindText, index, bytes);
        }

        public int bindBlob(int index, byte[] value) throws Throwable {
            return bindBytes(bindBlob, index, value);
        }

        public int bind(int index, Object value) throws Throwable {
            if (value == null) return bindNull(index);
            if (value instanceof byte[] bytes) return bindBlob(index, bytes);
            if (value instanceof String text) return bindString(index, text);
            if (value instanceof Byte
                || value instanceof Short
                || value instanceof Integer
                || value instanceof Long) {
                return bindLong(index, ((Number) value).longValue());
            }
            if (value instanceof Float || value instanceof Double) {
                return bindDouble(index, ((Number) value).doubleValue());
            }
            throw new IllegalArgumentException(
                "SQLite values must be nil, integer, floating point, string, or byte array");
        }

        private int bindBytes(
            MethodHandle method,
            int index,
            byte[] bytes
        ) throws Throwable {
            requireStatementOpen();
            if (bytes.length == 0) {
                return (int) method.invoke(raw, index, MemorySegment.NULL, 0L);
            }
            try (Arena local = Arena.ofConfined()) {
                MemorySegment data = local.allocate(bytes.length, 1);
                data.copyFrom(MemorySegment.ofArray(bytes));
                return (int) method.invoke(raw, index, data, (long) bytes.length);
            }
        }

        public int step() throws Throwable {
            requireStatementOpen();
            return (int) stmtStep.invoke(raw);
        }

        public int reset() throws Throwable {
            requireStatementOpen();
            return (int) stmtReset.invoke(raw);
        }

        public int clearBindings() throws Throwable {
            requireStatementOpen();
            return (int) stmtClearBindings.invoke(raw);
        }

        public boolean readonly() throws Throwable {
            requireStatementOpen();
            return (boolean) stmtReadonly.invoke(raw);
        }

        public int columnCount() throws Throwable {
            requireStatementOpen();
            return (int) columnCount.invoke(raw);
        }

        public String columnName(int index) throws Throwable {
            requireStatementOpen();
            return ownedString((MemorySegment) columnName.invoke(raw, index));
        }

        public int columnType(int index) throws Throwable {
            requireStatementOpen();
            return (int) columnType.invoke(raw, index);
        }

        public long columnLong(int index) throws Throwable {
            requireStatementOpen();
            return (long) columnInt64.invoke(raw, index);
        }

        public double columnDouble(int index) throws Throwable {
            requireStatementOpen();
            return (double) columnDouble.invoke(raw, index);
        }

        public byte[] columnBlob(int index) throws Throwable {
            requireStatementOpen();
            int length = (int) columnBytes.invoke(raw, index);
            if (length <= 0) return new byte[0];
            MemorySegment data = (MemorySegment) columnBlob.invoke(raw, index);
            if (isNull(data)) return new byte[0];
            return data.reinterpret(length).toArray(ValueLayout.JAVA_BYTE);
        }

        public String columnString(int index) throws Throwable {
            requireStatementOpen();
            int length = (int) columnBytes.invoke(raw, index);
            if (length <= 0) return "";
            MemorySegment data = (MemorySegment) columnText.invoke(raw, index);
            if (isNull(data)) return "";
            byte[] bytes = data.reinterpret(length).toArray(ValueLayout.JAVA_BYTE);
            return new String(bytes, StandardCharsets.UTF_8);
        }

        public Object columnValue(int index) throws Throwable {
            return switch (columnType(index)) {
                case NULL -> null;
                case INTEGER -> columnLong(index);
                case FLOAT -> columnDouble(index);
                case TEXT -> columnString(index);
                case BLOB -> columnBlob(index);
                default -> throw new IllegalStateException("unknown SQLite column type");
            };
        }

        private void requireStatementOpen() {
            connection.requireConnectionOpen();
            if (isNull(raw)) throw new IllegalStateException("SQLite statement is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                try {
                    stmtFinalize.invoke(raw);
                } catch (Throwable error) {
                    throw new IllegalStateException("failed to finalize SQLite statement", error);
                } finally {
                    raw = MemorySegment.NULL;
                }
            }
        }
    }
}
