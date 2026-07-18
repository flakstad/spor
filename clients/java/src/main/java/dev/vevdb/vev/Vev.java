// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package dev.vevdb.vev;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.lang.ref.Cleaner;
import java.util.UUID;
import java.util.Date;

public final class Vev implements AutoCloseable {
    private static final Linker LINKER = Linker.nativeLinker();
    private static final Cleaner CLEANER = Cleaner.create();
    public static final int ABI_VERSION = 1;
    public static final int COLUMN_ENTITY = 1;
    public static final int COLUMN_STRING = 2;
    public static final int COLUMN_INT = 3;
    public static final int COLUMN_MIXED = 4;
    public static final int COLUMN_BOOL = 5;
    public static final int COLUMN_FLOAT = 6;
    public static final int COLUMN_VALUE = 7;
    public static final int COLUMN_KEYWORD = 8;
    public static final int COLUMN_SYMBOL = 9;
    public static final int COLUMN_UUID = 10;
    public static final int COLUMN_INSTANT = 11;

    @FunctionalInterface
    public interface TxFunction {
        String apply(DB db, List<Object> args) throws Throwable;
    }

    @FunctionalInterface
    public interface QueryPredicate {
        boolean test(List<Object> args) throws Throwable;
    }

    @FunctionalInterface
    public interface QueryAggregate {
        String apply(List<Object> values) throws Throwable;
    }

    @FunctionalInterface
    public interface TxReportListener {
        void accept(Object report) throws Throwable;
    }

    private final Arena arena;
    private final Cleaner.Cleanable cleanable;
    private final SymbolLookup symbols;

    private final MethodHandle connOpenMemory;
    private final MethodHandle connClose;
    private final MethodHandle connDb;
    private final MethodHandle connFromDb;
    private final MethodHandle connListenTxReport;
    private final MethodHandle connUnlistenTxReport;
    private final MethodHandle connectionOpen;
    private final MethodHandle connectionOk;
    private final MethodHandle connectionError;
    private final MethodHandle connectionBackend;
    private final MethodHandle connectionPath;
    private final MethodHandle connectionBasisT;
    private final MethodHandle connectionTxCount;
    private final MethodHandle connectionTxIds;
    private final MethodHandle connectionTxDataEdn;
    private final MethodHandle connectionInfoEdn;
    private final MethodHandle connectionClose;
    private final MethodHandle connectionDb;
    private final MethodHandle connectionTransactEdnReport;
    private final MethodHandle connectionTransactEdnReportWithTxFns;
    private final MethodHandle connectionTxCommitReport;
    private final MethodHandle connectionTxCommitManyReport;
    private final MethodHandle connectionTxCommitLogicalManyReports;
    private final MethodHandle connectionTransactManyEdnReports;
    private final MethodHandle connectionCompactIndexes;
    private final MethodHandle connectionListenTxReport;
    private final MethodHandle connectionUnlistenTxReport;
    private final MethodHandle sqliteConnOpen;
    private final MethodHandle sqliteConnOk;
    private final MethodHandle sqliteConnError;
    private final MethodHandle sqliteConnClose;
    private final MethodHandle sqliteConnDb;
    private final MethodHandle sqliteConnTransactEdnReport;
    private final MethodHandle sqliteConnTxCommitReport;
    private final MethodHandle sqliteConnTransactManyEdnReports;
    private final MethodHandle sqliteConnCompactIndexes;
    private final MethodHandle connectionPreparedColumnBatchWithInputs;
    private final MethodHandle sqliteConnPreparedColumnBatchWithInputs;
    private final MethodHandle dbRetain;
    private final MethodHandle dbRelease;
    private final MethodHandle withEdn;
    private final MethodHandle withEdnReport;
    private final MethodHandle dbWithEdn;
    private final MethodHandle dbEntity;
    private final MethodHandle dbEntityLookupRefString;
    private final MethodHandle dbEntityIdent;
    private final MethodHandle entityFree;
    private final MethodHandle entityFound;
    private final MethodHandle entityId;
    private final MethodHandle entityContains;
    private final MethodHandle entityGet;
    private final MethodHandle entityValues;
    private final MethodHandle entityRef;
    private final MethodHandle entityRefs;
    private final MethodHandle entityTouch;
    private final MethodHandle stringFree;
    private final MethodHandle transactEdn;
    private final MethodHandle transactEdnReport;
    private final MethodHandle txReportFree;
    private final MethodHandle txReportValue;
    private final MethodHandle txReportEdn;
    private final MethodHandle txReportDbBefore;
    private final MethodHandle txReportDbAfter;
    private final MethodHandle txReportArrayFree;
    private final MethodHandle txReportArrayCount;
    private final MethodHandle txReportArrayGet;
    private final MethodHandle txCreate;
    private final MethodHandle txFree;
    private final MethodHandle txAddString;
    private final MethodHandle txAddKeyword;
    private final MethodHandle txAddSymbol;
    private final MethodHandle txAddEntity;
    private final MethodHandle txAddInt;
    private final MethodHandle txAddBool;
    private final MethodHandle txCommitReport;
    private final MethodHandle txDbWith;
    private final MethodHandle txFnRegistryCreate;
    private final MethodHandle txFnRegistryFree;
    private final MethodHandle txFnRegistryRegisterEdn;
    private final MethodHandle queryFnRegistryCreate;
    private final MethodHandle queryFnRegistryFree;
    private final MethodHandle queryFnRegistryRegisterPredicate;
    private final MethodHandle queryFnRegistryRegisterAggregate;
    private final MethodHandle transactEdnReportWithTxFns;
    private final MethodHandle withEdnReportWithTxFns;
    private final MethodHandle txFnArg;
    private final MethodHandle queryEdnWithInputs;
    private final MethodHandle prepareQueryEdn;
    private final MethodHandle preparedQueryEdn;
    private final MethodHandle parseClauseEdn;
    private final MethodHandle preparedQueryFree;
    private final MethodHandle queryPreparedResultWithRulesTextAndInputs;
    private final MethodHandle queryDbPreparedResultWithRulesTextAndInputs;
    private final MethodHandle queryDbPreparedColumnBatchWithRulesTextAndInputs;
    private final MethodHandle stmtCreate;
    private final MethodHandle stmtClear;
    private final MethodHandle stmtFree;
    private final MethodHandle stmtBindString;
    private final MethodHandle stmtBindStringCollection;
    private final MethodHandle stmtBindPullPatternEdn;
    private final MethodHandle queryStmtResult;
    private final MethodHandle queryDbStmtResult;
    private final MethodHandle queryDbStmtColumnBatch;
    private final MethodHandle queryPreparedColumnBatchWithInputs;
    private final MethodHandle queryPreparedResultWithInputs;
    private final MethodHandle queryDbPreparedResultWithInputs;
    private final MethodHandle queryDbPreparedResultWithInputsAndFns;
    private final MethodHandle queryRelationDbPreparedResultWithInputs;
    private final MethodHandle queryRelationDbPreparedRowCountWithInputs;
    private final MethodHandle queryDbPreparedProfileEdnWithInputs;
    private final MethodHandle queryDbPreparedProfileEdnWithRulesTextAndInputs;
    private final MethodHandle queryDbPreparedEntityColumnWithInputs;
    private final MethodHandle queryDbPreparedStringColumnWithInputs;
    private final MethodHandle u64ArrayFree;
    private final MethodHandle u64ArrayCount;
    private final MethodHandle u64ArrayValue;
    private final MethodHandle u64ArrayData;
    private final MethodHandle stringArrayFree;
    private final MethodHandle stringArrayCount;
    private final MethodHandle stringArrayDataArray;
    private final MethodHandle stringArrayLengthsData;
    private final MethodHandle queryDbPreparedEntityIntPairsWithInputs;
    private final MethodHandle entityIntPairsFree;
    private final MethodHandle entityIntPairsCount;
    private final MethodHandle entityIntPairsEntity;
    private final MethodHandle entityIntPairsValue;
    private final MethodHandle entityIntPairsEntitiesData;
    private final MethodHandle entityIntPairsValuesData;
    private final MethodHandle queryDbPreparedEntityStringIntTriplesWithInputs;
    private final MethodHandle queryDbPreparedColumnBatchWithInputs;
    private final MethodHandle queryRelationDbPreparedColumnBatchWithInputs;
    private final MethodHandle columnBatchFree;
    private final MethodHandle columnBatchKind;
    private final MethodHandle columnBatchCount;
    private final MethodHandle columnBatchColumnCount;
    private final MethodHandle columnBatchColumnKind;
    private final MethodHandle columnBatchEntitiesData;
    private final MethodHandle columnBatchIntsData;
    private final MethodHandle columnBatchStringDataArray;
    private final MethodHandle columnBatchStringLengthsData;
    private final MethodHandle columnBatchSecondStringDataArray;
    private final MethodHandle columnBatchSecondStringLengthsData;
    private final MethodHandle columnBatchColumnEntitiesData;
    private final MethodHandle columnBatchColumnIntsData;
    private final MethodHandle columnBatchColumnFloatsData;
    private final MethodHandle columnBatchColumnBoolsData;
    private final MethodHandle columnBatchColumnValueKindsData;
    private final MethodHandle columnBatchColumnValuesData;
    private final MethodHandle columnBatchColumnStringDataArray;
    private final MethodHandle columnBatchColumnStringLengthsData;
    private final MethodHandle columnBatchStringDictionaryCount;
    private final MethodHandle columnBatchStringDictionaryDataArray;
    private final MethodHandle columnBatchStringDictionaryLengthsData;
    private final MethodHandle columnBatchStringIndicesData;
    private final MethodHandle entityStringIntTriplesFree;
    private final MethodHandle entityStringIntTriplesCount;
    private final MethodHandle entityStringIntTriplesEntitiesData;
    private final MethodHandle entityStringIntTriplesIntsData;
    private final MethodHandle entityStringIntTriplesStringDataArray;
    private final MethodHandle entityStringIntTriplesStringLengthsData;
    private final MethodHandle entityStringIntTriplesStringDictionaryCount;
    private final MethodHandle entityStringIntTriplesStringDictionaryDataArray;
    private final MethodHandle entityStringIntTriplesStringDictionaryLengthsData;
    private final MethodHandle entityStringIntTriplesStringIndicesData;
    private final MethodHandle entityStringIntTriplesString;
    private final MethodHandle entityStringIntTriplesStringData;
    private final MethodHandle entityStringIntTriplesStringLen;
    private final MethodHandle pullEdn;
    private final MethodHandle preparePullPatternEdn;
    private final MethodHandle preparedPullPatternFree;
    private final MethodHandle preparedPullPatternOk;
    private final MethodHandle preparedPullPatternError;
    private final MethodHandle preparedPullPatternEdn;
    private final MethodHandle pullPrepared;
    private final MethodHandle pullLookupRefStringEdn;
    private final MethodHandle pullLookupRefStringPrepared;
    private final MethodHandle pullLookupRefKeywordEdn;
    private final MethodHandle pullLookupRefKeywordPrepared;
    private final MethodHandle pullLookupRefUuidEdn;
    private final MethodHandle pullLookupRefUuidPrepared;
    private final MethodHandle pullLookupRefEntityEdn;
    private final MethodHandle pullLookupRefEntityPrepared;
    private final MethodHandle pullLookupRefIntEdn;
    private final MethodHandle pullLookupRefIntPrepared;
    private final MethodHandle pullManyEdn;
    private final MethodHandle pullManyPrepared;
    private final MethodHandle pullManyLookupRefStringEdn;
    private final MethodHandle pullManyLookupRefStringPrepared;
    private final MethodHandle pullManyLookupRefUuidEdn;
    private final MethodHandle pullManyLookupRefUuidPrepared;
    private final MethodHandle valueHandleFree;
    private final MethodHandle valueHandleValue;
    private final MethodHandle valueHandleEdn;
    private final MethodHandle resultFree;
    private final MethodHandle resultOk;
    private final MethodHandle resultError;
    private final MethodHandle resultRowCount;
    private final MethodHandle resultValueCount;
    private final MethodHandle resultValueKind;
    private final MethodHandle resultValue;
    private final MethodHandle resultPullCount;
    private final MethodHandle resultPull;
    private final MethodHandle resultValueEntity;
    private final MethodHandle resultValueInt;
    private final MethodHandle resultValueBool;
    private final MethodHandle resultValueTextData;
    private final MethodHandle resultValueTextLen;
    private final MethodHandle valueKind;
    private final MethodHandle valueTextData;
    private final MethodHandle valueTextLen;
    private final MethodHandle valueEntity;
    private final MethodHandle valueInt;
    private final MethodHandle valueFloat;
    private final MethodHandle valueBool;
    private final MethodHandle valueItemCount;
    private final MethodHandle valueItem;
    private final MethodHandle valueMapCount;
    private final MethodHandle valueMapKey;
    private final MethodHandle valueMapValue;

    public static Path defaultLibraryPath() {
        String property = System.getProperty("vev.library");
        if (property != null && !property.isBlank()) {
            return Path.of(property);
        }
        String env = System.getenv("VEV_LIB");
        if (env != null && !env.isBlank()) {
            return Path.of(env);
        }
        Path localBuild = Path.of("build", "lib", platformLibraryName());
        if (Files.exists(localBuild)) {
            return localBuild;
        }
        return extractBundledLibrary();
    }

    public static Vev load() {
        return load(defaultLibraryPath());
    }

    public static Vev load(Path libraryPath) {
        return new Vev(libraryPath);
    }

    private static String platformLibraryName() {
        return System.mapLibraryName("vev");
    }

    private static String platformId() {
        String osName = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        String archName = System.getProperty("os.arch", "").toLowerCase(Locale.ROOT);

        String os;
        if (osName.contains("mac") || osName.contains("darwin")) {
            os = "darwin";
        } else if (osName.contains("linux")) {
            os = "linux";
        } else if (osName.contains("windows")) {
            os = "windows";
        } else {
            os = osName.replaceAll("[^a-z0-9]+", "-");
        }

        String arch;
        if (archName.equals("aarch64") || archName.equals("arm64")) {
            arch = "aarch64";
        } else if (archName.equals("x86_64") || archName.equals("amd64")) {
            arch = "x86_64";
        } else {
            arch = archName.replaceAll("[^a-z0-9_]+", "-");
        }

        return os + "-" + arch;
    }

    private static Path extractBundledLibrary() {
        String resource = "/dev/vevdb/vev/native/" + platformId() + "/" + platformLibraryName();
        try (InputStream input = Vev.class.getResourceAsStream(resource)) {
            if (input == null) {
                throw new IllegalStateException(
                    "could not find Vev native library. Set -Dvev.library=/path/to/" + platformLibraryName()
                    + ", set VEV_LIB, build build/lib/" + platformLibraryName()
                    + ", or include bundled resource " + resource);
            }
            Path dir = Files.createTempDirectory("vev-native-");
            Path library = dir.resolve(platformLibraryName());
            Files.copy(input, library, StandardCopyOption.REPLACE_EXISTING);
            library.toFile().deleteOnExit();
            dir.toFile().deleteOnExit();
            return library;
        } catch (IOException error) {
            throw new IllegalStateException("failed to extract bundled Vev native library", error);
        }
    }

    public Vev(Path libraryPath) {
        this.arena = Arena.ofShared();
        this.cleanable = CLEANER.register(this, arena::close);
        this.symbols = SymbolLookup.libraryLookup(libraryPath, arena);

        MethodHandle nativeAbiVersion = downcall(
            "vev_abi_version",
            FunctionDescriptor.of(ValueLayout.JAVA_INT));
        try {
            int actualAbiVersion = (int) nativeAbiVersion.invoke();
            if (actualAbiVersion != ABI_VERSION) {
                throw new IllegalStateException(
                    "incompatible Vev native ABI: Java requires "
                    + ABI_VERSION + ", native library provides " + actualAbiVersion);
            }
        } catch (RuntimeException | Error error) {
            cleanable.clean();
            throw error;
        } catch (Throwable error) {
            cleanable.clean();
            throw new IllegalStateException("failed to read Vev native ABI version", error);
        }

        this.connOpenMemory = downcall("vev_conn_open_memory", FunctionDescriptor.of(ValueLayout.ADDRESS));
        this.connClose = downcall("vev_conn_close", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.connDb = downcall("vev_conn_db", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connFromDb = downcall("vev_conn_from_db", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connListenTxReport = downcall("vev_conn_listen_tx_report", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connUnlistenTxReport = downcall("vev_conn_unlisten_tx_report", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionOpen = downcall("vev_connect", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionOk = downcall("vev_connection_ok", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.connectionError = downcall("vev_connection_error", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionBackend = downcall("vev_connection_backend", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionPath = downcall("vev_connection_path", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionBasisT = downcall("vev_connection_basis_t", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.connectionTxCount = downcall("vev_connection_tx_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.connectionTxIds = downcall("vev_connection_tx_ids", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionTxDataEdn = downcall("vev_connection_tx_data_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.connectionInfoEdn = downcall("vev_connection_info_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionClose = downcall("vev_connection_close", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.connectionDb = downcall("vev_connection_db", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionTransactEdnReport = downcall("vev_connection_transact_edn_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionTransactEdnReportWithTxFns = downcall("vev_connection_transact_edn_report_with_tx_fns", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionTxCommitReport = downcall("vev_connection_tx_commit_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionTxCommitManyReport = downcall("vev_connection_tx_commit_many_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.connectionTxCommitLogicalManyReports = downcall("vev_connection_tx_commit_logical_many_reports", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.connectionTransactManyEdnReports = downcall("vev_connection_transact_many_edn_reports", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.connectionCompactIndexes = downcall("vev_connection_compact_indexes", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.connectionListenTxReport = downcall("vev_connection_listen_tx_report", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.connectionUnlistenTxReport = downcall("vev_connection_unlisten_tx_report", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.sqliteConnOpen = downcall("vev_sqlite_conn_open", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.sqliteConnOk = downcall("vev_sqlite_conn_ok", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.sqliteConnError = downcall("vev_sqlite_conn_error", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.sqliteConnClose = downcall("vev_sqlite_conn_close", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.sqliteConnDb = downcall("vev_sqlite_conn_db", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.sqliteConnTransactEdnReport = downcall("vev_sqlite_conn_transact_edn_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.sqliteConnTxCommitReport = downcall("vev_sqlite_conn_tx_commit_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.sqliteConnTransactManyEdnReports = downcall("vev_sqlite_conn_transact_many_edn_reports", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.sqliteConnCompactIndexes = downcall("vev_sqlite_conn_compact_indexes", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.connectionPreparedColumnBatchWithInputs = downcall("vev_connection_prepared_column_batch_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.sqliteConnPreparedColumnBatchWithInputs = downcall("vev_sqlite_conn_prepared_column_batch_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.dbRetain = downcall("vev_db_retain", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.dbRelease = downcall("vev_db_release", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.withEdn = downcall("vev_with_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.withEdnReport = downcall("vev_with_edn_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.dbWithEdn = downcall("vev_db_with_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.dbEntity = downcall("vev_db_entity", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.dbEntityLookupRefString = downcall("vev_db_entity_lookup_ref_string", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.dbEntityIdent = downcall("vev_db_entity_ident", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityFree = downcall("vev_entity_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.entityFound = downcall("vev_entity_found", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.entityId = downcall("vev_entity_id", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.entityContains = downcall("vev_entity_contains", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityGet = downcall("vev_entity_get", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityValues = downcall("vev_entity_values", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityRef = downcall("vev_entity_ref", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityRefs = downcall("vev_entity_refs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityTouch = downcall("vev_entity_touch", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.stringFree = downcall("vev_string_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.transactEdn = downcall("vev_transact_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.transactEdnReport = downcall("vev_transact_edn_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txReportFree = downcall("vev_tx_report_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.txReportValue = downcall("vev_tx_report_value", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txReportEdn = downcall("vev_tx_report_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txReportDbBefore = downcall("vev_tx_report_db_before", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txReportDbAfter = downcall("vev_tx_report_db_after", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txReportArrayFree = downcall("vev_tx_report_array_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.txReportArrayCount = downcall("vev_tx_report_array_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.txReportArrayGet = downcall("vev_tx_report_array_get", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.txCreate = downcall("vev_tx_create", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.txFree = downcall("vev_tx_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.txAddString = downcall("vev_tx_add_string", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txAddKeyword = downcall("vev_tx_add_keyword", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txAddSymbol = downcall("vev_tx_add_symbol", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txAddEntity = downcall("vev_tx_add_entity", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.txAddInt = downcall("vev_tx_add_int", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.txAddBool = downcall("vev_tx_add_bool", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_BOOLEAN));
        this.txCommitReport = downcall("vev_tx_commit_report", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txDbWith = downcall("vev_tx_db_with", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txFnRegistryCreate = downcall("vev_tx_fn_registry_create", FunctionDescriptor.of(ValueLayout.ADDRESS));
        this.txFnRegistryFree = downcall("vev_tx_fn_registry_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.txFnRegistryRegisterEdn = downcall("vev_tx_fn_registry_register_edn", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryFnRegistryCreate = downcall("vev_query_fn_registry_create", FunctionDescriptor.of(ValueLayout.ADDRESS));
        this.queryFnRegistryFree = downcall("vev_query_fn_registry_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.queryFnRegistryRegisterPredicate = downcall("vev_query_fn_registry_register_predicate", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryFnRegistryRegisterAggregate = downcall("vev_query_fn_registry_register_aggregate", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.transactEdnReportWithTxFns = downcall("vev_transact_edn_report_with_tx_fns", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.withEdnReportWithTxFns = downcall("vev_with_edn_report_with_tx_fns", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.txFnArg = downcall("vev_tx_fn_arg", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.queryEdnWithInputs = downcall("vev_query_edn_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.prepareQueryEdn = downcall("vev_prepare_query_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.preparedQueryEdn = downcall("vev_prepared_query_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.parseClauseEdn = downcall("vev_parse_clause_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.preparedQueryFree = downcall("vev_prepared_query_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.queryPreparedResultWithRulesTextAndInputs = downcall("vev_query_prepared_result_with_rules_text_and_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedResultWithRulesTextAndInputs = downcall("vev_query_db_prepared_result_with_rules_text_and_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedColumnBatchWithRulesTextAndInputs = downcall("vev_query_db_prepared_column_batch_with_rules_text_and_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.stmtCreate = downcall("vev_stmt_create", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.stmtClear = downcall("vev_stmt_clear", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.stmtFree = downcall("vev_stmt_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.stmtBindString = downcall("vev_stmt_bind_string", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.stmtBindStringCollection = downcall("vev_stmt_bind_string_collection", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.stmtBindPullPatternEdn = downcall("vev_stmt_bind_pull_pattern_edn", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryStmtResult = downcall("vev_query_stmt_result", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbStmtResult = downcall("vev_query_db_stmt_result", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbStmtColumnBatch = downcall("vev_query_db_stmt_column_batch", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryPreparedColumnBatchWithInputs = downcall("vev_query_prepared_column_batch_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryPreparedResultWithInputs = downcall("vev_query_prepared_result_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedResultWithInputs = downcall("vev_query_db_prepared_result_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedResultWithInputsAndFns = downcall("vev_query_db_prepared_result_with_inputs_and_fns", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryRelationDbPreparedResultWithInputs = downcall("vev_query_relation_db_prepared_result_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryRelationDbPreparedRowCountWithInputs = downcall("vev_query_relation_db_prepared_row_count_with_inputs", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedProfileEdnWithInputs = downcall("vev_query_db_prepared_profile_edn_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedProfileEdnWithRulesTextAndInputs = downcall("vev_query_db_prepared_profile_edn_with_rules_text_and_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedEntityColumnWithInputs = downcall("vev_query_db_prepared_entity_column_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedStringColumnWithInputs = downcall("vev_query_db_prepared_string_column_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.u64ArrayFree = downcall("vev_u64_array_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.u64ArrayCount = downcall("vev_u64_array_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.u64ArrayValue = downcall("vev_u64_array_value", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.u64ArrayData = downcall("vev_u64_array_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.stringArrayFree = downcall("vev_string_array_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.stringArrayCount = downcall("vev_string_array_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.stringArrayDataArray = downcall("vev_string_array_data_array", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.stringArrayLengthsData = downcall("vev_string_array_lengths_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedEntityIntPairsWithInputs = downcall("vev_query_db_prepared_entity_int_pairs_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityIntPairsFree = downcall("vev_entity_int_pairs_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.entityIntPairsCount = downcall("vev_entity_int_pairs_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.entityIntPairsEntity = downcall("vev_entity_int_pairs_entity", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.entityIntPairsValue = downcall("vev_entity_int_pairs_value", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.entityIntPairsEntitiesData = downcall("vev_entity_int_pairs_entities_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityIntPairsValuesData = downcall("vev_entity_int_pairs_values_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedEntityStringIntTriplesWithInputs = downcall("vev_query_db_prepared_entity_string_int_triples_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryDbPreparedColumnBatchWithInputs = downcall("vev_query_db_prepared_column_batch_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.queryRelationDbPreparedColumnBatchWithInputs = downcall("vev_query_relation_db_prepared_column_batch_with_inputs", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchFree = downcall("vev_column_batch_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.columnBatchKind = downcall("vev_column_batch_kind", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.columnBatchCount = downcall("vev_column_batch_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.columnBatchColumnCount = downcall("vev_column_batch_column_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.columnBatchColumnKind = downcall("vev_column_batch_column_kind", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchEntitiesData = downcall("vev_column_batch_entities_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchIntsData = downcall("vev_column_batch_ints_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchStringDataArray = downcall("vev_column_batch_string_data_array", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchStringLengthsData = downcall("vev_column_batch_string_lengths_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchSecondStringDataArray = downcall("vev_column_batch_second_string_data_array", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchSecondStringLengthsData = downcall("vev_column_batch_second_string_lengths_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchColumnEntitiesData = downcall("vev_column_batch_column_entities_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchColumnIntsData = downcall("vev_column_batch_column_ints_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchColumnFloatsData = downcall("vev_column_batch_column_floats_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchColumnBoolsData = downcall("vev_column_batch_column_bools_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchColumnValueKindsData = downcall("vev_column_batch_column_value_kinds_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchColumnValuesData = downcall("vev_column_batch_column_values_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchColumnStringDataArray = downcall("vev_column_batch_column_string_data_array", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchColumnStringLengthsData = downcall("vev_column_batch_column_string_lengths_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.columnBatchStringDictionaryCount = downcall("vev_column_batch_string_dictionary_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.columnBatchStringDictionaryDataArray = downcall("vev_column_batch_string_dictionary_data_array", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchStringDictionaryLengthsData = downcall("vev_column_batch_string_dictionary_lengths_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.columnBatchStringIndicesData = downcall("vev_column_batch_string_indices_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesFree = downcall("vev_entity_string_int_triples_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.entityStringIntTriplesCount = downcall("vev_entity_string_int_triples_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.entityStringIntTriplesEntitiesData = downcall("vev_entity_string_int_triples_entities_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesIntsData = downcall("vev_entity_string_int_triples_ints_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesStringDataArray = downcall("vev_entity_string_int_triples_string_data_array", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesStringLengthsData = downcall("vev_entity_string_int_triples_string_lengths_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesStringDictionaryCount = downcall("vev_entity_string_int_triples_string_dictionary_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.entityStringIntTriplesStringDictionaryDataArray = downcall("vev_entity_string_int_triples_string_dictionary_data_array", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesStringDictionaryLengthsData = downcall("vev_entity_string_int_triples_string_dictionary_lengths_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesStringIndicesData = downcall("vev_entity_string_int_triples_string_indices_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.entityStringIntTriplesString = downcall("vev_entity_string_int_triples_string", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.entityStringIntTriplesStringData = downcall("vev_entity_string_int_triples_string_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.entityStringIntTriplesStringLen = downcall("vev_entity_string_int_triples_string_len", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.pullEdn = downcall("vev_pull_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.preparePullPatternEdn = downcall("vev_prepare_pull_pattern_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.preparedPullPatternFree = downcall("vev_prepared_pull_pattern_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.preparedPullPatternOk = downcall("vev_prepared_pull_pattern_ok", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.preparedPullPatternError = downcall("vev_prepared_pull_pattern_error", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.preparedPullPatternEdn = downcall("vev_prepared_pull_pattern_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.pullPrepared = downcall("vev_pull_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.pullLookupRefStringEdn = downcall("vev_pull_lookup_ref_string_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.pullLookupRefStringPrepared = downcall("vev_pull_lookup_ref_string_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.pullLookupRefKeywordEdn = downcall("vev_pull_lookup_ref_keyword_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.pullLookupRefKeywordPrepared = downcall("vev_pull_lookup_ref_keyword_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.pullLookupRefUuidEdn = downcall("vev_pull_lookup_ref_uuid_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.pullLookupRefUuidPrepared = downcall("vev_pull_lookup_ref_uuid_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.pullLookupRefEntityEdn = downcall("vev_pull_lookup_ref_entity_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.pullLookupRefEntityPrepared = downcall("vev_pull_lookup_ref_entity_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.pullLookupRefIntEdn = downcall("vev_pull_lookup_ref_int_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.pullLookupRefIntPrepared = downcall("vev_pull_lookup_ref_int_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.pullManyEdn = downcall("vev_pull_many_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.pullManyPrepared = downcall("vev_pull_many_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.pullManyLookupRefStringEdn = downcall("vev_pull_many_lookup_ref_string_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.pullManyLookupRefStringPrepared = downcall("vev_pull_many_lookup_ref_string_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.pullManyLookupRefUuidEdn = downcall("vev_pull_many_lookup_ref_uuid_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.pullManyLookupRefUuidPrepared = downcall("vev_pull_many_lookup_ref_uuid_prepared", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.valueHandleFree = downcall("vev_value_handle_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.valueHandleValue = downcall("vev_value_handle_value", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.valueHandleEdn = downcall("vev_value_handle_edn", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.resultFree = downcall("vev_result_free", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.resultOk = downcall("vev_result_ok", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.resultError = downcall("vev_result_error", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.resultRowCount = downcall("vev_result_row_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.resultValueCount = downcall("vev_result_value_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.resultValueKind = downcall("vev_result_value_kind", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.resultValue = downcall("vev_result_value", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.resultPullCount = downcall("vev_result_pull_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.resultPull = downcall("vev_result_pull", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.resultValueEntity = downcall("vev_result_value_entity", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.resultValueInt = downcall("vev_result_value_int", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.resultValueBool = downcall("vev_result_value_bool", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.resultValueTextData = downcall("vev_result_value_text_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.resultValueTextLen = downcall("vev_result_value_text_len", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        this.valueKind = downcall("vev_value_kind", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.valueTextData = downcall("vev_value_text_data", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.valueTextLen = downcall("vev_value_text_len", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.valueEntity = downcall("vev_value_entity", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.valueInt = downcall("vev_value_int", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.valueFloat = downcall("vev_value_float", FunctionDescriptor.of(ValueLayout.JAVA_DOUBLE, ValueLayout.ADDRESS));
        this.valueBool = downcall("vev_value_bool", FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        this.valueItemCount = downcall("vev_value_item_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.valueItem = downcall("vev_value_item", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.valueMapCount = downcall("vev_value_map_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.valueMapKey = downcall("vev_value_map_key", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
        this.valueMapValue = downcall("vev_value_map_value", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT));
    }

    public Connection openMemory() throws Throwable {
        return createConn();
    }

    public Connection createConn() throws Throwable {
        MemorySegment raw = (MemorySegment) connOpenMemory.invoke();
        if (isNull(raw)) throw new IllegalStateException("failed to open Vev connection");
        return new Connection(raw);
    }

    public DurableConnection connect(Path path) throws Throwable {
        return connect(path.toString());
    }

    public DurableConnection connect(String uri) throws Throwable {
        try (Arena local = Arena.ofConfined()) {
            MemorySegment raw = (MemorySegment) connectionOpen.invoke(local.allocateUtf8String(uri));
            if (isNull(raw)) throw new IllegalStateException("failed to connect Vev durable connection");
            boolean ok = (boolean) connectionOk.invoke(raw);
            if (!ok) {
                String error = ownedString((MemorySegment) connectionError.invoke(raw));
                closeHandle(connectionClose, raw);
                throw new IllegalStateException(error);
            }
            return new DurableConnection(raw);
        }
    }

    public SQLiteConnection openSqlite(Path path) throws Throwable {
        try (Arena local = Arena.ofConfined()) {
            MemorySegment raw = (MemorySegment) sqliteConnOpen.invoke(local.allocateUtf8String(path.toString()));
            if (isNull(raw)) throw new IllegalStateException("failed to open SQLite-backed Vev connection");
            boolean ok = (boolean) sqliteConnOk.invoke(raw);
            if (!ok) {
                String error = ownedString((MemorySegment) sqliteConnError.invoke(raw));
                closeHandle(sqliteConnClose, raw);
                throw new IllegalStateException(error);
            }
            return new SQLiteConnection(raw);
        }
    }

    public SQLiteConnection openSqlite(String path) throws Throwable {
        return openSqlite(Path.of(path));
    }

    public Connection connFromDb(DB db) throws Throwable {
        // Resident/in-memory compatibility only. Durable DB handles are
        // immutable values and should be queried directly.
        db.requireOpen();
        MemorySegment raw = (MemorySegment) connFromDb.invoke(db.handle.raw);
        if (isNull(raw)) throw new IllegalStateException("failed to create Vev connection from DB");
        return new Connection(raw);
    }

    public PreparedQuery prepare(String query) throws Throwable {
        try (Arena local = Arena.ofConfined()) {
            MemorySegment raw = (MemorySegment) prepareQueryEdn.invoke(local.allocateUtf8String(query));
            if (isNull(raw)) throw new IllegalStateException("failed to prepare query");
            return new PreparedQuery(raw);
        }
    }

    public PreparedPullPattern preparePullPattern(String pattern) throws Throwable {
        try (Arena local = Arena.ofConfined()) {
            MemorySegment raw = (MemorySegment) preparePullPatternEdn.invoke(local.allocateUtf8String(pattern));
            if (isNull(raw)) throw new IllegalStateException("failed to prepare pull pattern");
            if (!((boolean) preparedPullPatternOk.invoke(raw))) {
                String error = ownedString((MemorySegment) preparedPullPatternError.invoke(raw));
                closeHandle(preparedPullPatternFree, raw);
                throw new IllegalStateException(error);
            }
            return new PreparedPullPattern(raw);
        }
    }

    public String parseClauseEdn(String clause) throws Throwable {
        try (Arena local = Arena.ofConfined()) {
            return ownedString((MemorySegment) parseClauseEdn.invoke(local.allocateUtf8String(clause)));
        }
    }

    public ResultSet queryRelationDb(String rows, PreparedQuery query, String inputs) throws Throwable {
        query.requireOpen();
        try (Arena local = Arena.ofConfined()) {
            return new ResultSet((MemorySegment) queryRelationDbPreparedResultWithInputs.invoke(
                local.allocateUtf8String(rows),
                query.raw,
                local.allocateUtf8String(inputs)));
        }
    }

    public ColumnResult queryRelationDbColumns(String rows, PreparedQuery query, String inputs) throws Throwable {
        query.requireOpen();
        try (Arena local = Arena.ofConfined()) {
            return columnResultFromBatch((MemorySegment) queryRelationDbPreparedColumnBatchWithInputs.invoke(
                local.allocateUtf8String(rows),
                query.raw,
                local.allocateUtf8String(inputs)));
        }
    }

    public long queryRelationDbRowCount(String rows, PreparedQuery query, String inputs) throws Throwable {
        query.requireOpen();
        try (Arena local = Arena.ofConfined()) {
            return (long) queryRelationDbPreparedRowCountWithInputs.invoke(
                local.allocateUtf8String(rows),
                query.raw,
                local.allocateUtf8String(inputs));
        }
    }

    public ResultSet query(Map<String, ?> request) throws Throwable {
        Object query = request.get("query");
        Object args = request.get("args");
        if (!(query instanceof String queryText)) {
            throw new IllegalArgumentException("query request requires string key: query");
        }
        if (!(args instanceof List<?> argList) || argList.isEmpty()) {
            throw new IllegalArgumentException("query request requires non-empty list key: args");
        }

        Object source = argList.get(0);
        String inputs = inputsEdn(argList.subList(1, argList.size()));
        try (PreparedQuery prepared = prepare(queryText)) {
            if (source instanceof Connection conn) {
                return conn.query(prepared, inputs);
            }
            if (source instanceof DurableConnection conn) {
                try (DB db = conn.db()) {
                    return db.query(prepared, inputs);
                }
            }
            if (source instanceof SQLiteConnection conn) {
                try (DB db = conn.db()) {
                    return db.query(prepared, inputs);
                }
            }
            if (source instanceof DB db) {
                return db.query(prepared, inputs);
            }
            throw new IllegalArgumentException("query request first arg must be a Vev connection or DB");
        }
    }

    public List<List<Object>> queryRows(Map<String, ?> request) throws Throwable {
        try (ResultSet result = query(request)) {
            return result.rows();
        }
    }

    public List<Map<Object, Object>> queryMaps(Map<String, ?> request) throws Throwable {
        Object query = request.get("query");
        if (!(query instanceof String queryText)) {
            throw new IllegalArgumentException("query request requires string key: query");
        }
        ReturnKeys returnKeys = returnKeys(queryText);
        if (returnKeys == null) {
            throw new IllegalArgumentException("query does not contain :keys, :strs, or :syms");
        }
        return rowsToMaps(returnKeys.keys(), queryRows(request));
    }

    public TxBuilder txBuilder(int capacity) throws Throwable {
        MemorySegment raw = (MemorySegment) txCreate.invoke(Math.max(0, capacity));
        if (isNull(raw)) throw new IllegalStateException("failed to create transaction builder");
        return new TxBuilder(raw);
    }

    public TxFunctionRegistry txFunctionRegistry() throws Throwable {
        MemorySegment raw = (MemorySegment) txFnRegistryCreate.invoke();
        if (isNull(raw)) throw new IllegalStateException("failed to create transaction function registry");
        return new TxFunctionRegistry(raw);
    }

    public QueryFunctionRegistry queryFunctionRegistry() throws Throwable {
        MemorySegment raw = (MemorySegment) queryFnRegistryCreate.invoke();
        if (isNull(raw)) throw new IllegalStateException("failed to create query function registry");
        return new QueryFunctionRegistry(raw);
    }

    @Override
    public void close() {
        cleanable.clean();
    }

    private MethodHandle downcall(String name, FunctionDescriptor descriptor) {
        MemorySegment symbol = symbols.find(name).orElseThrow(() -> new IllegalStateException("missing symbol: " + name));
        return LINKER.downcallHandle(symbol, descriptor);
    }

    private String ownedString(MemorySegment ptr) throws Throwable {
        if (isNull(ptr)) return "";
        String out = ptr.reinterpret(Long.MAX_VALUE).getUtf8String(0);
        stringFree.invoke(ptr);
        return out;
    }

    private String textOf(MemorySegment value) throws Throwable {
        int length = (int) valueTextLen.invoke(value);
        return borrowedUtf8String((MemorySegment) valueTextData.invoke(value), length);
    }

    private String resultTextOf(MemorySegment result, int row, int column) throws Throwable {
        int length = (int) resultValueTextLen.invoke(result, row, column);
        return borrowedUtf8String((MemorySegment) resultValueTextData.invoke(result, row, column), length);
    }

    private String borrowedUtf8String(MemorySegment data, int length) {
        if (length <= 0) return "";
        if (isNull(data)) return "";
        byte[] bytes = data.reinterpret(length).toArray(ValueLayout.JAVA_BYTE);
        return new String(bytes, StandardCharsets.UTF_8);
    }

    private Object valueToJava(MemorySegment value) throws Throwable {
        int kind = (int) valueKind.invoke(value);
        return switch (kind) {
            case 0 -> null;
            case 1 -> new Entity((long) valueEntity.invoke(value));
            case 3 -> (long) valueInt.invoke(value);
            case 4 -> (double) valueFloat.invoke(value);
            case 5 -> (boolean) valueBool.invoke(value);
            case 2 -> textOf(value);
            case 6 -> new Keyword(textOf(value));
            case 7 -> new Symbol(textOf(value));
            case 10 -> UUID.fromString(textOf(value));
            case 12 -> new Date((long) valueInt.invoke(value));
            case 8 -> {
                int count = (int) valueItemCount.invoke(value);
                List<Object> items = new ArrayList<>(count);
                for (int i = 0; i < count; i++) {
                    items.add(valueToJava((MemorySegment) valueItem.invoke(value, i)));
                }
                yield items;
            }
            case 11 -> {
                int count = (int) valueItemCount.invoke(value);
                Set<Object> items = new LinkedHashSet<>(count);
                for (int i = 0; i < count; i++) {
                    items.add(valueToJava((MemorySegment) valueItem.invoke(value, i)));
                }
                yield items;
            }
            case 9 -> {
                int count = (int) valueMapCount.invoke(value);
                List<Entry> entries = new ArrayList<>(count);
                for (int i = 0; i < count; i++) {
                    Object key = valueToJava((MemorySegment) valueMapKey.invoke(value, i));
                    Object item = valueToJava((MemorySegment) valueMapValue.invoke(value, i));
                    entries.add(new Entry(key, item));
                }
                yield new MapValue(entries);
            }
            default -> textOf(value);
        };
    }

    private Object resultValueToJava(MemorySegment result, int row, int column, int kind) throws Throwable {
        return switch (kind) {
            case 0 -> null;
            case 1 -> new Entity((long) resultValueEntity.invoke(result, row, column));
            case 2 -> resultTextOf(result, row, column);
            case 6 -> new Keyword(resultTextOf(result, row, column));
            case 7 -> new Symbol(resultTextOf(result, row, column));
            case 10 -> UUID.fromString(resultTextOf(result, row, column));
            case 12 -> new Date((long) resultValueInt.invoke(result, row, column));
            case 3 -> (long) resultValueInt.invoke(result, row, column);
            case 5 -> (boolean) resultValueBool.invoke(result, row, column);
            default -> valueToJava((MemorySegment) resultValue.invoke(result, row, column));
        };
    }

    private long[] columnLongs(MemorySegment data, int count) {
        if (count == 0 || isNull(data)) return new long[0];
        return data.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
    }

    private int[] columnInts(MemorySegment data, int count) {
        if (count == 0 || isNull(data)) return new int[0];
        return data.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
    }

    private double[] columnDoubles(MemorySegment data, int count) {
        if (count == 0 || isNull(data)) return new double[0];
        return data.reinterpret((long) count * Double.BYTES).toArray(ValueLayout.JAVA_DOUBLE);
    }

    private boolean[] columnBools(MemorySegment data, int count) {
        if (count == 0 || isNull(data)) return new boolean[0];
        byte[] bytes = data.reinterpret((long) count).toArray(ValueLayout.JAVA_BYTE);
        boolean[] out = new boolean[count];
        for (int index = 0; index < count; index++) {
            out[index] = bytes[index] != 0;
        }
        return out;
    }

    private String[] columnStrings(MemorySegment raw, int column, int count) throws Throwable {
        if (count == 0) return new String[0];
        MemorySegment dataArrayRaw = (MemorySegment) columnBatchColumnStringDataArray.invoke(raw, column);
        MemorySegment lengthsRaw = (MemorySegment) columnBatchColumnStringLengthsData.invoke(raw, column);
        if (isNull(dataArrayRaw) || isNull(lengthsRaw)) return new String[0];
        MemorySegment dataArray = dataArrayRaw.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
        int[] lengths = lengthsRaw.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
        String[] out = new String[count];
        for (int index = 0; index < count; index++) {
            MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
            out[index] = borrowedUtf8String(data, lengths[index]);
        }
        return out;
    }

    private Object[] columnMixedValues(MemorySegment raw, int column, int count) throws Throwable {
        int[] valueKinds = columnInts((MemorySegment) columnBatchColumnValueKindsData.invoke(raw, column), count);
        if (valueKinds.length != count) return null;
        long[] entities = columnLongs((MemorySegment) columnBatchColumnEntitiesData.invoke(raw, column), count);
        long[] ints = columnLongs((MemorySegment) columnBatchColumnIntsData.invoke(raw, column), count);
        double[] floats = columnDoubles((MemorySegment) columnBatchColumnFloatsData.invoke(raw, column), count);
        boolean[] bools = columnBools((MemorySegment) columnBatchColumnBoolsData.invoke(raw, column), count);
        String[] strings = columnStrings(raw, column, count);
        Object[] out = new Object[count];
        for (int row = 0; row < count; row++) {
            out[row] = switch (valueKinds[row]) {
                case 0 -> null;
                case 1 -> new Entity(entities[row]);
                case 2 -> strings[row];
                case 3 -> ints[row];
                case 4 -> floats[row];
                case 5 -> bools[row];
                case 6 -> new Keyword(strings[row]);
                case 7 -> new Symbol(strings[row]);
                case 10 -> UUID.fromString(strings[row]);
                case 12 -> new Date(ints[row]);
                default -> strings[row];
            };
        }
        return out;
    }

    private Object[] columnValueHandles(MemorySegment raw, int column, int count) throws Throwable {
        if (count == 0) return new Object[0];
        MemorySegment valuesData = (MemorySegment) columnBatchColumnValuesData.invoke(raw, column);
        if (isNull(valuesData)) return null;
        MemorySegment valueArray = valuesData.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
        Object[] out = new Object[count];
        for (int row = 0; row < count; row++) {
            MemorySegment value = valueArray.get(ValueLayout.ADDRESS, (long) row * ValueLayout.ADDRESS.byteSize());
            out[row] = valueToJava(value);
        }
        return out;
    }

    private ColumnResult columnResultFromBatch(MemorySegment raw) throws Throwable {
        if (isNull(raw)) return null;
        try {
            int count = (int) columnBatchCount.invoke(raw);
            int columnCount = (int) columnBatchColumnCount.invoke(raw);
            if (columnCount <= 0) return null;
            int[] kinds = new int[columnCount];
            Object[] columns = new Object[columnCount];
            for (int column = 0; column < columnCount; column++) {
                int kind = (int) columnBatchColumnKind.invoke(raw, column);
                kinds[column] = kind;
                columns[column] = switch (kind) {
                    case COLUMN_ENTITY -> columnLongs((MemorySegment) columnBatchColumnEntitiesData.invoke(raw, column), count);
                    case COLUMN_STRING, COLUMN_KEYWORD, COLUMN_SYMBOL, COLUMN_UUID -> columnStrings(raw, column, count);
                    case COLUMN_INT -> columnLongs((MemorySegment) columnBatchColumnIntsData.invoke(raw, column), count);
                    case COLUMN_INSTANT -> columnLongs((MemorySegment) columnBatchColumnIntsData.invoke(raw, column), count);
                    case COLUMN_BOOL -> columnBools((MemorySegment) columnBatchColumnBoolsData.invoke(raw, column), count);
                    case COLUMN_FLOAT -> columnDoubles((MemorySegment) columnBatchColumnFloatsData.invoke(raw, column), count);
                    case COLUMN_MIXED -> columnMixedValues(raw, column, count);
                    case COLUMN_VALUE -> columnValueHandles(raw, column, count);
                    default -> null;
                };
                if (columns[column] == null) return null;
            }
            return new ColumnResult(count, kinds, columns);
        } finally {
            columnBatchFree.invoke(raw);
        }
    }

    private void closeHandle(MethodHandle handle, MemorySegment segment) {
        try {
            handle.invoke(segment);
        } catch (Throwable error) {
            throw new RuntimeException(error);
        }
    }

    private DB retainedDb(MemorySegment raw) throws Throwable {
        MemorySegment retained = (MemorySegment) dbRetain.invoke(raw);
        if (isNull(retained)) throw new IllegalStateException("failed to retain DB snapshot");
        return new DB(retained);
    }

    private List<Object> txFnArgs(int argc, MemorySegment args) throws Throwable {
        List<Object> out = new ArrayList<>(Math.max(0, argc));
        for (int index = 0; index < argc; index++) {
            out.add(valueToJava((MemorySegment) txFnArg.invoke(args, index)));
        }
        return out;
    }

    private MemorySegment txFnCallback(TxFunctionRegistry registry, TxFunction function, MemorySegment user, MemorySegment db, int argc, MemorySegment args) throws Throwable {
        try (DB callbackDb = retainedDb(db)) {
            String result = function.apply(callbackDb, txFnArgs(argc, args));
            if (result == null) return MemorySegment.NULL;
            return registry.arena.allocateUtf8String(result);
        }
    }

    private boolean queryPredicateCallback(QueryPredicate predicate, MemorySegment user, int argc, MemorySegment args) throws Throwable {
        return predicate.test(txFnArgs(argc, args));
    }

    private MemorySegment queryAggregateCallback(QueryFunctionRegistry registry, QueryAggregate aggregate, MemorySegment user, int argc, MemorySegment args) throws Throwable {
        String result = aggregate.apply(txFnArgs(argc, args));
        if (result == null) return MemorySegment.NULL;
        return registry.arena.allocateUtf8String(result);
    }

    private void txReportListenerCallback(TxReportListener listener, MemorySegment user, MemorySegment report) throws Throwable {
        listener.accept(valueToJava((MemorySegment) txReportValue.invoke(report)));
    }

    private static boolean isNull(MemorySegment segment) {
        return segment == null || segment.equals(MemorySegment.NULL);
    }

    private static MemorySegment longArray(Arena arena, long[] values) {
        MemorySegment array = arena.allocateArray(ValueLayout.JAVA_LONG, values.length);
        for (int i = 0; i < values.length; i++) {
            array.setAtIndex(ValueLayout.JAVA_LONG, i, values[i]);
        }
        return array;
    }

    private static String inputsEdn(List<?> inputs) {
        StringBuilder out = new StringBuilder();
        out.append("[");
        for (int i = 0; i < inputs.size(); i++) {
            if (i > 0) out.append(" ");
            appendEdn(out, inputs.get(i));
        }
        out.append("]");
        return out.toString();
    }

    private static void appendEdn(StringBuilder out, Object value) {
        if (value == null) {
            out.append("nil");
        } else if (value instanceof String text) {
            appendEdnString(out, text);
        } else if (value instanceof Keyword keyword) {
            out.append(keyword.text());
        } else if (value instanceof Entity entity) {
            out.append("[:vev/entity ").append(entity.id()).append("]");
        } else if (value instanceof Date instant) {
            out.append("#inst \"").append(instant.toInstant()).append("\"");
        } else if (value instanceof Number || value instanceof Boolean) {
            out.append(value);
        } else if (value instanceof List<?> items) {
            out.append("[");
            for (int i = 0; i < items.size(); i++) {
                if (i > 0) out.append(" ");
                appendEdn(out, items.get(i));
            }
            out.append("]");
        } else if (value instanceof Set<?> items) {
            out.append("#{");
            int index = 0;
            for (Object item : items) {
                if (index > 0) out.append(" ");
                appendEdn(out, item);
                index++;
            }
            out.append("}");
        } else {
            throw new IllegalArgumentException("unsupported EDN input value: " + value);
        }
    }

    private static void appendEdnString(StringBuilder out, String text) {
        out.append('"');
        for (int i = 0; i < text.length(); i++) {
            char ch = text.charAt(i);
            switch (ch) {
                case '\\' -> out.append("\\\\");
                case '"' -> out.append("\\\"");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> out.append(ch);
            }
        }
        out.append('"');
    }

    private static ReturnKeys returnKeys(String queryText) {
        String normalized = queryText
            .replace('[', ' ')
            .replace(']', ' ')
            .replace('{', ' ')
            .replace('}', ' ')
            .replace('(', ' ')
            .replace(')', ' ');
        String[] tokens = normalized.trim().isEmpty() ? new String[0] : normalized.trim().split("\\s+");
        for (int index = 0; index < tokens.length; index++) {
            String token = tokens[index];
            if (":keys".equals(token) || ":strs".equals(token) || ":syms".equals(token)) {
                List<Object> keys = new ArrayList<>();
                for (int keyIndex = index + 1; keyIndex < tokens.length; keyIndex++) {
                    String key = stripStringToken(tokens[keyIndex]);
                    if (":in".equals(key) || ":where".equals(key) || ":with".equals(key)) {
                        break;
                    }
                    keys.add(returnKey(token, key));
                }
                return new ReturnKeys(token, keys);
            }
        }
        return null;
    }

    private static String stripStringToken(String token) {
        if (token.length() >= 2 && token.startsWith("\"") && token.endsWith("\"")) {
            return token.substring(1, token.length() - 1);
        }
        return token;
    }

    private static Object returnKey(String marker, String key) {
        return switch (marker) {
            case ":keys" -> new Keyword(key.startsWith(":") ? key : ":" + key);
            case ":syms" -> new Symbol(key.startsWith(":") ? key.substring(1) : key);
            default -> key.startsWith(":") ? key.substring(1) : key;
        };
    }

    private static List<Map<Object, Object>> rowsToMaps(List<Object> keys, List<List<Object>> rows) {
        List<Map<Object, Object>> out = new ArrayList<>(rows.size());
        for (List<Object> row : rows) {
            Map<Object, Object> item = new LinkedHashMap<>();
            int count = Math.min(keys.size(), row.size());
            for (int index = 0; index < count; index++) {
                item.put(keys.get(index), row.get(index));
            }
            out.add(item);
        }
        return out;
    }

    private static final class NativeHandle implements Runnable {
        private final MethodHandle closeHandle;
        private MemorySegment raw;

        private NativeHandle(MethodHandle closeHandle, MemorySegment raw) {
            this.closeHandle = closeHandle;
            this.raw = raw;
        }

        @Override
        public void run() {
            if (!isNull(raw)) {
                try {
                    closeHandle.invoke(raw);
                } catch (Throwable error) {
                    throw new RuntimeException(error);
                } finally {
                    raw = MemorySegment.NULL;
                }
            }
        }
    }

    public record Entity(long id) {}
    public record Keyword(String text) {}
    public record Symbol(String text) {}
    public record Entry(Object key, Object value) {}
    public record ReturnKeys(String marker, List<Object> keys) {}

    public record ColumnResult(int rowCount, int[] kinds, Object[] columns) {
        public List<List<Object>> rows() {
            List<List<Object>> out = new ArrayList<>(rowCount);
            for (int row = 0; row < rowCount; row++) {
                List<Object> values = new ArrayList<>(kinds.length);
                for (int column = 0; column < kinds.length; column++) {
                    values.add(valueAt(column, row));
                }
                out.add(values);
            }
            return out;
        }

        private Object valueAt(int column, int row) {
            Object values = columns[column];
            return switch (kinds[column]) {
                case COLUMN_ENTITY -> new Entity(((long[]) values)[row]);
                case COLUMN_INT -> ((long[]) values)[row];
                case COLUMN_STRING -> ((String[]) values)[row];
                case COLUMN_KEYWORD -> new Keyword(((String[]) values)[row]);
                case COLUMN_SYMBOL -> new Symbol(((String[]) values)[row]);
                case COLUMN_UUID -> UUID.fromString(((String[]) values)[row]);
                case COLUMN_INSTANT -> new Date(((long[]) values)[row]);
                case COLUMN_BOOL -> ((boolean[]) values)[row];
                case COLUMN_FLOAT -> ((double[]) values)[row];
                case COLUMN_MIXED -> ((Object[]) values)[row];
                case COLUMN_VALUE -> ((Object[]) values)[row];
                default -> throw new IllegalStateException("unsupported column kind: " + kinds[column]);
            };
        }
    }

    public record MapValue(List<Entry> entries) {
        public Object get(String key) {
            for (Entry entry : entries) {
                Object entryKey = entry.key();
                if (key.equals(entryKey)
                        || (entryKey instanceof Keyword keyword && key.equals(keyword.text()))) {
                    return entry.value();
                }
            }
            return null;
        }
    }

    public final class TxReport implements AutoCloseable {
        private MemorySegment raw;
        private final boolean owned;

        private TxReport(MemorySegment raw) {
            this(raw, true);
        }

        private TxReport(MemorySegment raw, boolean owned) {
            if (isNull(raw)) throw new IllegalStateException("transaction returned null report");
            this.raw = raw;
            this.owned = owned;
        }

        public Object value() throws Throwable {
            requireOpen();
            return valueToJava((MemorySegment) txReportValue.invoke(raw));
        }

        public String edn() throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) txReportEdn.invoke(raw));
        }

        public DB dbBefore() throws Throwable {
            requireOpen();
            MemorySegment db = (MemorySegment) txReportDbBefore.invoke(raw);
            if (isNull(db)) throw new IllegalStateException("transaction report has no db-before");
            return new DB(db);
        }

        public DB dbAfter() throws Throwable {
            requireOpen();
            MemorySegment db = (MemorySegment) txReportDbAfter.invoke(raw);
            if (isNull(db)) throw new IllegalStateException("transaction report has no db-after");
            return new DB(db);
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("transaction report is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                if (owned) {
                    closeHandle(txReportFree, raw);
                }
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class TxReportArray implements AutoCloseable {
        private MemorySegment raw;

        private TxReportArray(MemorySegment raw) {
            if (isNull(raw)) throw new IllegalStateException("transaction returned null report array");
            this.raw = raw;
        }

        public int size() throws Throwable {
            requireOpen();
            return (int) txReportArrayCount.invoke(raw);
        }

        public TxReport get(int index) throws Throwable {
            requireOpen();
            MemorySegment report = (MemorySegment) txReportArrayGet.invoke(raw, index);
            return new TxReport(report, false);
        }

        public List<Object> values() throws Throwable {
            requireOpen();
            int count = size();
            ArrayList<Object> values = new ArrayList<>(count);
            for (int index = 0; index < count; index++) {
                values.add(get(index).value());
            }
            return values;
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("transaction report array is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(txReportArrayFree, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class TxFunctionRegistry implements AutoCloseable {
        private final Arena arena;
        private final List<TxFunction> functions;
        private MemorySegment raw;

        private TxFunctionRegistry(MemorySegment raw) {
            this.raw = raw;
            this.arena = Arena.ofShared();
            this.functions = new ArrayList<>();
        }

        public TxFunctionRegistry register(String ident, TxFunction function) throws Throwable {
            requireOpen();
            if (ident == null || ident.isBlank()) throw new IllegalArgumentException("transaction function ident is required");
            if (function == null) throw new IllegalArgumentException("transaction function callback is required");
            MethodHandle callback = MethodHandles.lookup()
                .findVirtual(
                    Vev.class,
                    "txFnCallback",
                    MethodType.methodType(
                        MemorySegment.class,
                        TxFunctionRegistry.class,
                        TxFunction.class,
                        MemorySegment.class,
                        MemorySegment.class,
                        int.class,
                        MemorySegment.class))
                .bindTo(Vev.this)
                .bindTo(this)
                .bindTo(function);
            MemorySegment stub = LINKER.upcallStub(
                callback,
                FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.ADDRESS),
                arena);
            boolean ok = (boolean) txFnRegistryRegisterEdn.invoke(
                raw,
                arena.allocateUtf8String(ident),
                stub,
                MemorySegment.NULL);
            if (!ok) throw new IllegalStateException("failed to register transaction function: " + ident);
            functions.add(function);
            return this;
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("transaction function registry is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(txFnRegistryFree, raw);
                raw = MemorySegment.NULL;
            }
            arena.close();
        }
    }

    public final class QueryFunctionRegistry implements AutoCloseable {
        private final Arena arena;
        private final List<Object> functions;
        private MemorySegment raw;

        private QueryFunctionRegistry(MemorySegment raw) {
            this.raw = raw;
            this.arena = Arena.ofShared();
            this.functions = new ArrayList<>();
        }

        public QueryFunctionRegistry registerPredicate(String ident, QueryPredicate predicate) throws Throwable {
            requireOpen();
            if (ident == null || ident.isBlank()) throw new IllegalArgumentException("query predicate ident is required");
            if (predicate == null) throw new IllegalArgumentException("query predicate callback is required");
            MethodHandle callback = MethodHandles.lookup()
                .findVirtual(
                    Vev.class,
                    "queryPredicateCallback",
                    MethodType.methodType(
                        boolean.class,
                        QueryPredicate.class,
                        MemorySegment.class,
                        int.class,
                        MemorySegment.class))
                .bindTo(Vev.this)
                .bindTo(predicate);
            MemorySegment stub = LINKER.upcallStub(
                callback,
                FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.ADDRESS),
                arena);
            boolean ok = (boolean) queryFnRegistryRegisterPredicate.invoke(
                raw,
                arena.allocateUtf8String(ident),
                stub,
                MemorySegment.NULL);
            if (!ok) throw new IllegalStateException("failed to register query predicate: " + ident);
            functions.add(predicate);
            return this;
        }

        public QueryFunctionRegistry registerAggregate(String ident, QueryAggregate aggregate) throws Throwable {
            requireOpen();
            if (ident == null || ident.isBlank()) throw new IllegalArgumentException("query aggregate ident is required");
            if (aggregate == null) throw new IllegalArgumentException("query aggregate callback is required");
            MethodHandle callback = MethodHandles.lookup()
                .findVirtual(
                    Vev.class,
                    "queryAggregateCallback",
                    MethodType.methodType(
                        MemorySegment.class,
                        QueryFunctionRegistry.class,
                        QueryAggregate.class,
                        MemorySegment.class,
                        int.class,
                        MemorySegment.class))
                .bindTo(Vev.this)
                .bindTo(this)
                .bindTo(aggregate);
            MemorySegment stub = LINKER.upcallStub(
                callback,
                FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.ADDRESS),
                arena);
            boolean ok = (boolean) queryFnRegistryRegisterAggregate.invoke(
                raw,
                arena.allocateUtf8String(ident),
                stub,
                MemorySegment.NULL);
            if (!ok) throw new IllegalStateException("failed to register query aggregate: " + ident);
            functions.add(aggregate);
            return this;
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("query function registry is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(queryFnRegistryFree, raw);
                raw = MemorySegment.NULL;
            }
            arena.close();
        }
    }

    public final class TxReportListenerRegistration implements AutoCloseable {
        private final Arena arena;
        private final MemorySegment connRaw;
        private final MethodHandle unlistenFn;
        private final String name;
        private final TxReportListener listener;
        private boolean open;

        private TxReportListenerRegistration(Arena arena, Connection conn, String name, TxReportListener listener) {
            this(arena, conn.raw, connUnlistenTxReport, name, listener);
        }

        private TxReportListenerRegistration(Arena arena, DurableConnection conn, String name, TxReportListener listener) {
            this(arena, conn.raw, connectionUnlistenTxReport, name, listener);
        }

        private TxReportListenerRegistration(Arena arena, MemorySegment connRaw, MethodHandle unlistenFn, String name, TxReportListener listener) {
            this.arena = arena;
            this.connRaw = connRaw;
            this.unlistenFn = unlistenFn;
            this.name = name;
            this.listener = listener;
            this.open = true;
        }

        @Override
        public void close() {
            if (open) {
                try (Arena local = Arena.ofConfined()) {
                    if (!isNull(connRaw)) {
                        unlistenFn.invoke(connRaw, local.allocateUtf8String(name));
                    }
                } catch (Throwable error) {
                    throw new RuntimeException(error);
                } finally {
                    open = false;
                    arena.close();
                }
            }
        }
    }

    public final class Connection implements AutoCloseable {
        private MemorySegment raw;

        private Connection(MemorySegment raw) {
            this.raw = raw;
        }

        public String transact(String tx) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                return ownedString((MemorySegment) transactEdn.invoke(raw, local.allocateUtf8String(tx)));
            }
        }

        public TxReport transactReport(String tx) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                return new TxReport((MemorySegment) transactEdnReport.invoke(raw, local.allocateUtf8String(tx)));
            }
        }

        public TxReport transactReport(String tx, TxFunctionRegistry registry) throws Throwable {
            registry.requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new TxReport((MemorySegment) transactEdnReportWithTxFns.invoke(
                    raw,
                    local.allocateUtf8String(tx),
                    registry.raw));
            }
        }

        public TxReport transactReport(TxBuilder tx) throws Throwable {
            tx.requireOpen();
            return new TxReport((MemorySegment) txCommitReport.invoke(raw, tx.raw));
        }

        public TxReportListenerRegistration listen(String name, TxReportListener listener) throws Throwable {
            requireOpen();
            if (name == null || name.isBlank()) throw new IllegalArgumentException("listener name is required");
            if (listener == null) throw new IllegalArgumentException("transaction listener callback is required");
            Arena listenerArena = Arena.ofShared();
            MethodHandle callback = MethodHandles.lookup()
                .findVirtual(
                    Vev.class,
                    "txReportListenerCallback",
                    MethodType.methodType(void.class, TxReportListener.class, MemorySegment.class, MemorySegment.class))
                .bindTo(Vev.this)
                .bindTo(listener);
            MemorySegment stub = LINKER.upcallStub(
                callback,
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.ADDRESS),
                listenerArena);
            boolean ok;
            try (Arena local = Arena.ofConfined()) {
                ok = (boolean) connListenTxReport.invoke(raw, local.allocateUtf8String(name), stub, MemorySegment.NULL);
            }
            if (!ok) {
                listenerArena.close();
                throw new IllegalStateException("failed to register transaction listener: " + name);
            }
            return new TxReportListenerRegistration(listenerArena, this, name, listener);
        }

        public boolean unlisten(String name) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return (boolean) connUnlistenTxReport.invoke(raw, local.allocateUtf8String(name));
            }
        }

        public String queryText(String query, String inputs) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                return ownedString((MemorySegment) queryEdnWithInputs.invoke(raw, local.allocateUtf8String(query), local.allocateUtf8String(inputs)));
            }
        }

        public ResultSet query(PreparedQuery query, String inputs) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                return new ResultSet((MemorySegment) queryPreparedResultWithInputs.invoke(raw, query.raw, local.allocateUtf8String(inputs)));
            }
        }

        public ColumnResult queryColumns(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return columnResultFromBatch((MemorySegment) queryPreparedColumnBatchWithInputs.invoke(
                    raw,
                    query.raw,
                    local.allocateUtf8String(inputs)));
            }
        }

        public ResultSet query(PreparedQuery query, String rules, String inputs) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                return new ResultSet((MemorySegment) queryPreparedResultWithRulesTextAndInputs.invoke(
                    raw,
                    query.raw,
                    local.allocateUtf8String(rules),
                    local.allocateUtf8String(inputs)));
            }
        }

        public ResultSet query(Statement stmt) throws Throwable {
            return new ResultSet((MemorySegment) queryStmtResult.invoke(raw, stmt.raw));
        }

        public DB db() throws Throwable {
            requireOpen();
            MemorySegment db = (MemorySegment) connDb.invoke(raw);
            if (isNull(db)) throw new IllegalStateException("failed to retain DB snapshot");
            return new DB(db);
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("connection is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(connClose, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class DurableConnection implements AutoCloseable {
        private MemorySegment raw;

        private DurableConnection(MemorySegment raw) {
            this.raw = raw;
        }

        public TxReport transactReport(String tx) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new TxReport((MemorySegment) connectionTransactEdnReport.invoke(raw, local.allocateUtf8String(tx)));
            }
        }

        public TxReport transactReport(String tx, TxFunctionRegistry registry) throws Throwable {
            requireOpen();
            registry.requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new TxReport((MemorySegment) connectionTransactEdnReportWithTxFns.invoke(
                    raw,
                    local.allocateUtf8String(tx),
                    registry.raw));
            }
        }

        public TxReport transactReport(TxBuilder tx) throws Throwable {
            requireOpen();
            tx.requireOpen();
            return new TxReport((MemorySegment) connectionTxCommitReport.invoke(raw, tx.raw));
        }

        public TxReport transactReport(List<TxBuilder> txs) throws Throwable {
            requireOpen();
            if (txs == null || txs.isEmpty()) {
                throw new IllegalArgumentException("bulk transaction requires at least one builder");
            }
            try (Arena local = Arena.ofConfined()) {
                MemorySegment builders = local.allocate(
                    ValueLayout.ADDRESS.byteSize() * txs.size(),
                    ValueLayout.ADDRESS.byteAlignment());
                for (int index = 0; index < txs.size(); index++) {
                    TxBuilder tx = txs.get(index);
                    if (tx == null) {
                        throw new IllegalArgumentException("bulk transaction builder cannot be null");
                    }
                    tx.requireOpen();
                    builders.setAtIndex(ValueLayout.ADDRESS, index, tx.raw);
                }
                return new TxReport((MemorySegment) connectionTxCommitManyReport.invoke(raw, builders, txs.size()));
            }
        }

        public TxReportArray transactLogicalReports(List<TxBuilder> txs) throws Throwable {
            requireOpen();
            if (txs == null) {
                throw new IllegalArgumentException("logical group commit builders cannot be null");
            }
            if (txs.isEmpty()) {
                return new TxReportArray((MemorySegment) connectionTxCommitLogicalManyReports.invoke(raw, MemorySegment.NULL, 0));
            }
            try (Arena local = Arena.ofConfined()) {
                MemorySegment builders = local.allocate(
                    ValueLayout.ADDRESS.byteSize() * txs.size(),
                    ValueLayout.ADDRESS.byteAlignment());
                for (int index = 0; index < txs.size(); index++) {
                    TxBuilder tx = txs.get(index);
                    if (tx == null) {
                        throw new IllegalArgumentException("logical group commit builder cannot be null");
                    }
                    tx.requireOpen();
                    builders.setAtIndex(ValueLayout.ADDRESS, index, tx.raw);
                }
                return new TxReportArray((MemorySegment) connectionTxCommitLogicalManyReports.invoke(raw, builders, txs.size()));
            }
        }

        public TxReportArray transactLogicalEdnReports(List<String> txs) throws Throwable {
            requireOpen();
            if (txs == null) {
                throw new IllegalArgumentException("logical EDN transaction group cannot be null");
            }
            if (txs.isEmpty()) {
                return new TxReportArray((MemorySegment) connectionTransactManyEdnReports.invoke(raw, MemorySegment.NULL, 0));
            }
            try (Arena local = Arena.ofConfined()) {
                MemorySegment texts = local.allocate(
                    ValueLayout.ADDRESS.byteSize() * txs.size(),
                    ValueLayout.ADDRESS.byteAlignment());
                for (int index = 0; index < txs.size(); index++) {
                    String tx = txs.get(index);
                    if (tx == null) {
                        throw new IllegalArgumentException("logical EDN transaction cannot be null");
                    }
                    texts.setAtIndex(ValueLayout.ADDRESS, index, local.allocateUtf8String(tx));
                }
                return new TxReportArray((MemorySegment) connectionTransactManyEdnReports.invoke(raw, texts, txs.size()));
            }
        }

        public boolean compactIndexes() throws Throwable {
            requireOpen();
            return (boolean) connectionCompactIndexes.invoke(raw);
        }

        public ColumnResult queryColumns(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return columnResultFromBatch((MemorySegment) connectionPreparedColumnBatchWithInputs.invoke(
                    raw,
                    query.raw,
                    local.allocateUtf8String(inputs)));
            }
        }

        public TxReportListenerRegistration listen(String name, TxReportListener listener) throws Throwable {
            requireOpen();
            if (name == null || name.isBlank()) throw new IllegalArgumentException("listener name is required");
            if (listener == null) throw new IllegalArgumentException("transaction listener callback is required");
            Arena listenerArena = Arena.ofShared();
            MethodHandle callback = MethodHandles.lookup()
                .findVirtual(
                    Vev.class,
                    "txReportListenerCallback",
                    MethodType.methodType(void.class, TxReportListener.class, MemorySegment.class, MemorySegment.class))
                .bindTo(Vev.this)
                .bindTo(listener);
            MemorySegment stub = LINKER.upcallStub(
                callback,
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.ADDRESS),
                listenerArena);
            boolean ok;
            try (Arena local = Arena.ofConfined()) {
                ok = (boolean) connectionListenTxReport.invoke(raw, local.allocateUtf8String(name), stub, MemorySegment.NULL);
            }
            if (!ok) {
                listenerArena.close();
                throw new IllegalStateException("failed to register transaction listener: " + name);
            }
            return new TxReportListenerRegistration(listenerArena, this, name, listener);
        }

        public boolean unlisten(String name) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return (boolean) connectionUnlistenTxReport.invoke(raw, local.allocateUtf8String(name));
            }
        }

        public DB db() throws Throwable {
            requireOpen();
            MemorySegment db = (MemorySegment) connectionDb.invoke(raw);
            if (isNull(db)) throw new IllegalStateException("failed to retain DB snapshot");
            return new DB(db);
        }

        public String backend() throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) connectionBackend.invoke(raw));
        }

        public String path() throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) connectionPath.invoke(raw));
        }

        public long basisT() throws Throwable {
            requireOpen();
            return (long) connectionBasisT.invoke(raw);
        }

        public long txCount() throws Throwable {
            requireOpen();
            return (long) connectionTxCount.invoke(raw);
        }

        public long[] txIds() throws Throwable {
            requireOpen();
            MemorySegment ids = (MemorySegment) connectionTxIds.invoke(raw);
            if (isNull(ids)) return new long[0];
            try {
                int count = (int) u64ArrayCount.invoke(ids);
                if (count == 0) return new long[0];
                MemorySegment data = (MemorySegment) u64ArrayData.invoke(ids);
                if (isNull(data)) return new long[0];
                return data.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
            } finally {
                u64ArrayFree.invoke(ids);
            }
        }

        public String txDataEdn(long tx) throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) connectionTxDataEdn.invoke(raw, tx));
        }

        public String infoEdn() throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) connectionInfoEdn.invoke(raw));
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("durable connection is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(connectionClose, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class SQLiteConnection implements AutoCloseable {
        private MemorySegment raw;

        private SQLiteConnection(MemorySegment raw) {
            this.raw = raw;
        }

        public TxReport transactReport(String tx) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new TxReport((MemorySegment) sqliteConnTransactEdnReport.invoke(raw, local.allocateUtf8String(tx)));
            }
        }

        public TxReport transactReport(TxBuilder tx) throws Throwable {
            requireOpen();
            tx.requireOpen();
            return new TxReport((MemorySegment) sqliteConnTxCommitReport.invoke(raw, tx.raw));
        }

        public TxReportArray transactLogicalEdnReports(List<String> txs) throws Throwable {
            requireOpen();
            if (txs == null) {
                throw new IllegalArgumentException("logical EDN transaction group cannot be null");
            }
            if (txs.isEmpty()) {
                return new TxReportArray((MemorySegment) sqliteConnTransactManyEdnReports.invoke(raw, MemorySegment.NULL, 0));
            }
            try (Arena local = Arena.ofConfined()) {
                MemorySegment texts = local.allocate(
                    ValueLayout.ADDRESS.byteSize() * txs.size(),
                    ValueLayout.ADDRESS.byteAlignment());
                for (int index = 0; index < txs.size(); index++) {
                    String tx = txs.get(index);
                    if (tx == null) {
                        throw new IllegalArgumentException("logical EDN transaction cannot be null");
                    }
                    texts.setAtIndex(ValueLayout.ADDRESS, index, local.allocateUtf8String(tx));
                }
                return new TxReportArray((MemorySegment) sqliteConnTransactManyEdnReports.invoke(raw, texts, txs.size()));
            }
        }

        public boolean compactIndexes() throws Throwable {
            requireOpen();
            return (boolean) sqliteConnCompactIndexes.invoke(raw);
        }

        public ColumnResult queryColumns(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return columnResultFromBatch((MemorySegment) sqliteConnPreparedColumnBatchWithInputs.invoke(
                    raw,
                    query.raw,
                    local.allocateUtf8String(inputs)));
            }
        }

        public DB db() throws Throwable {
            requireOpen();
            MemorySegment db = (MemorySegment) sqliteConnDb.invoke(raw);
            if (isNull(db)) throw new IllegalStateException("failed to retain DB snapshot");
            return new DB(db);
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("SQLite-backed connection is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(sqliteConnClose, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class DB implements AutoCloseable {
        private final NativeHandle handle;
        private final Cleaner.Cleanable cleanable;

        private DB(MemorySegment raw) {
            this.handle = new NativeHandle(dbRelease, raw);
            this.cleanable = CLEANER.register(this, handle);
        }

        public DB retain() throws Throwable {
            requireOpen();
            MemorySegment retained = (MemorySegment) dbRetain.invoke(handle.raw);
            if (isNull(retained)) throw new IllegalStateException("failed to retain DB snapshot");
            return new DB(retained);
        }

        public EntityView entity(long entity) throws Throwable {
            requireOpen();
            MemorySegment raw = (MemorySegment) dbEntity.invoke(handle.raw, entity);
            if (isNull(raw)) throw new IllegalStateException("failed to create entity view");
            return new EntityView(raw);
        }

        public EntityView entityLookupRefString(String attr, String value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) dbEntityLookupRefString.invoke(
                    handle.raw,
                    local.allocateUtf8String(attr),
                    local.allocateUtf8String(value));
                if (isNull(raw)) throw new IllegalStateException("failed to create lookup-ref entity view");
                return new EntityView(raw);
            }
        }

        public EntityView entityIdent(String ident) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) dbEntityIdent.invoke(handle.raw, local.allocateUtf8String(ident));
                if (isNull(raw)) throw new IllegalStateException("failed to create ident entity view");
                return new EntityView(raw);
            }
        }

        public ResultSet query(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new ResultSet((MemorySegment) queryDbPreparedResultWithInputs.invoke(handle.raw, query.raw, local.allocateUtf8String(inputs)));
            }
        }

        public ResultSet query(PreparedQuery query, String inputs, QueryFunctionRegistry registry) throws Throwable {
            requireOpen();
            registry.requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new ResultSet((MemorySegment) queryDbPreparedResultWithInputsAndFns.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs),
                    registry.raw));
            }
        }

        public String profileEdn(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return ownedString((MemorySegment) queryDbPreparedProfileEdnWithInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs)));
            }
        }

        public String profileEdn(PreparedQuery query, String rules, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return ownedString((MemorySegment) queryDbPreparedProfileEdnWithRulesTextAndInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(rules),
                    local.allocateUtf8String(inputs)));
            }
        }

        public ResultSet query(PreparedQuery query, String rules, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new ResultSet((MemorySegment) queryDbPreparedResultWithRulesTextAndInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(rules),
                    local.allocateUtf8String(inputs)));
            }
        }

        public ColumnResult queryColumns(PreparedQuery query, String rules, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) queryDbPreparedColumnBatchWithRulesTextAndInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(rules),
                    local.allocateUtf8String(inputs));
                return columnResultFromBatch(raw);
            }
        }

        public long[] queryEntityColumn(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) queryDbPreparedEntityColumnWithInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs));
                if (isNull(raw)) return null;
                try {
                    int count = (int) u64ArrayCount.invoke(raw);
                    if (count == 0) return new long[0];
                    MemorySegment data = (MemorySegment) u64ArrayData.invoke(raw);
                    if (isNull(data)) return new long[0];
                    return data.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                } finally {
                    u64ArrayFree.invoke(raw);
                }
            }
        }

        public String[] queryStringColumn(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) queryDbPreparedStringColumnWithInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs));
                if (isNull(raw)) return null;
                try {
                    int count = (int) stringArrayCount.invoke(raw);
                    if (count == 0) return new String[0];
                    MemorySegment dataArrayRaw = (MemorySegment) stringArrayDataArray.invoke(raw);
                    MemorySegment lengthsRaw = (MemorySegment) stringArrayLengthsData.invoke(raw);
                    if (isNull(dataArrayRaw) || isNull(lengthsRaw)) return new String[0];
                    MemorySegment dataArray = dataArrayRaw.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
                    int[] lengths = lengthsRaw.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
                    String[] out = new String[count];
                    for (int index = 0; index < count; index++) {
                        MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
                        out[index] = borrowedUtf8String(data, lengths[index]);
                    }
                    return out;
                } finally {
                    stringArrayFree.invoke(raw);
                }
            }
        }

        public long[][] queryEntityIntPairs(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) queryDbPreparedEntityIntPairsWithInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs));
                if (isNull(raw)) return null;
                try {
                    int count = (int) entityIntPairsCount.invoke(raw);
                    if (count == 0) return new long[0][2];
                    MemorySegment entityData = (MemorySegment) entityIntPairsEntitiesData.invoke(raw);
                    MemorySegment valueData = (MemorySegment) entityIntPairsValuesData.invoke(raw);
                    if (isNull(entityData) || isNull(valueData)) return new long[0][2];
                    long[] entities = entityData.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                    long[] values = valueData.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                    long[][] out = new long[count][2];
                    for (int index = 0; index < count; index++) {
                        out[index][0] = entities[index];
                        out[index][1] = values[index];
                    }
                    return out;
                } finally {
                    entityIntPairsFree.invoke(raw);
                }
            }
        }

        public long[][] queryEntityIntPairColumns(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) queryDbPreparedEntityIntPairsWithInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs));
                if (isNull(raw)) return null;
                try {
                    int count = (int) entityIntPairsCount.invoke(raw);
                    if (count == 0) return new long[][] { new long[0], new long[0] };
                    MemorySegment entityData = (MemorySegment) entityIntPairsEntitiesData.invoke(raw);
                    MemorySegment valueData = (MemorySegment) entityIntPairsValuesData.invoke(raw);
                    if (isNull(entityData) || isNull(valueData)) return new long[][] { new long[0], new long[0] };
                    long[] entities = entityData.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                    long[] values = valueData.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                    return new long[][] { entities, values };
                } finally {
                    entityIntPairsFree.invoke(raw);
                }
            }
        }

        public Object[] queryEntityStringIntTripleColumns(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) queryDbPreparedEntityStringIntTriplesWithInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs));
                if (isNull(raw)) return null;
                try {
                    int count = (int) entityStringIntTriplesCount.invoke(raw);
                    if (count == 0) return new Object[] { new long[0], new String[0], new long[0] };
                    MemorySegment entityData = (MemorySegment) entityStringIntTriplesEntitiesData.invoke(raw);
                    MemorySegment intData = (MemorySegment) entityStringIntTriplesIntsData.invoke(raw);
                    if (isNull(entityData) || isNull(intData)) return new Object[] { new long[0], new String[0], new long[0] };
                    long[] entities = entityData.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                    long[] ints = intData.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                    String[] strings = new String[count];
                    int dictionaryCount = (int) entityStringIntTriplesStringDictionaryCount.invoke(raw);
                    MemorySegment dictionaryDataArray = (MemorySegment) entityStringIntTriplesStringDictionaryDataArray.invoke(raw);
                    MemorySegment dictionaryLengthsData = (MemorySegment) entityStringIntTriplesStringDictionaryLengthsData.invoke(raw);
                    MemorySegment stringIndicesData = (MemorySegment) entityStringIntTriplesStringIndicesData.invoke(raw);
                    if (dictionaryCount > 0
                            && !isNull(dictionaryDataArray)
                            && !isNull(dictionaryLengthsData)
                            && !isNull(stringIndicesData)) {
                        MemorySegment dataArray = dictionaryDataArray.reinterpret((long) dictionaryCount * ValueLayout.ADDRESS.byteSize());
                        int[] lengths = dictionaryLengthsData.reinterpret((long) dictionaryCount * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
                        int[] indices = stringIndicesData.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
                        String[] dictionary = new String[dictionaryCount];
                        for (int index = 0; index < dictionaryCount; index++) {
                            MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
                            dictionary[index] = borrowedUtf8String(data, lengths[index]);
                        }
                        for (int index = 0; index < count; index++) {
                            strings[index] = dictionary[indices[index]];
                        }
                    } else {
                        MemorySegment stringDataArray = (MemorySegment) entityStringIntTriplesStringDataArray.invoke(raw);
                        MemorySegment stringLengthsData = (MemorySegment) entityStringIntTriplesStringLengthsData.invoke(raw);
                        if (!isNull(stringDataArray) && !isNull(stringLengthsData)) {
                            MemorySegment dataArray = stringDataArray.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
                            int[] lengths = stringLengthsData.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
                            for (int index = 0; index < count; index++) {
                                MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
                                strings[index] = borrowedUtf8String(data, lengths[index]);
                            }
                        } else {
                            for (int index = 0; index < count; index++) {
                                int length = (int) entityStringIntTriplesStringLen.invoke(raw, index);
                                MemorySegment data = (MemorySegment) entityStringIntTriplesStringData.invoke(raw, index);
                                strings[index] = borrowedUtf8String(data, length);
                            }
                        }
                    }
                    return new Object[] { entities, strings, ints };
                } finally {
                    entityStringIntTriplesFree.invoke(raw);
                }
            }
        }

        private long[] longColumn(MemorySegment data, int count) {
            if (count == 0 || isNull(data)) return new long[0];
            return data.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
        }

        private int[] intColumn(MemorySegment data, int count) {
            if (count == 0 || isNull(data)) return new int[0];
            return data.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
        }

        private double[] doubleColumn(MemorySegment data, int count) {
            if (count == 0 || isNull(data)) return new double[0];
            return data.reinterpret((long) count * Double.BYTES).toArray(ValueLayout.JAVA_DOUBLE);
        }

        private boolean[] boolColumn(MemorySegment data, int count) {
            if (count == 0 || isNull(data)) return new boolean[0];
            byte[] bytes = data.reinterpret((long) count).toArray(ValueLayout.JAVA_BYTE);
            boolean[] out = new boolean[count];
            for (int index = 0; index < count; index++) {
                out[index] = bytes[index] != 0;
            }
            return out;
        }

        private String[] columnBatchStrings(MemorySegment raw, int count) throws Throwable {
            if (count == 0) return new String[0];
            int dictionaryCount = (int) columnBatchStringDictionaryCount.invoke(raw);
            MemorySegment dictionaryDataArray = (MemorySegment) columnBatchStringDictionaryDataArray.invoke(raw);
            MemorySegment dictionaryLengthsData = (MemorySegment) columnBatchStringDictionaryLengthsData.invoke(raw);
            MemorySegment stringIndicesData = (MemorySegment) columnBatchStringIndicesData.invoke(raw);
            if (dictionaryCount > 0
                    && !isNull(dictionaryDataArray)
                    && !isNull(dictionaryLengthsData)
                    && !isNull(stringIndicesData)) {
                MemorySegment dataArray = dictionaryDataArray.reinterpret((long) dictionaryCount * ValueLayout.ADDRESS.byteSize());
                int[] lengths = dictionaryLengthsData.reinterpret((long) dictionaryCount * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
                int[] indices = stringIndicesData.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
                String[] dictionary = new String[dictionaryCount];
                for (int index = 0; index < dictionaryCount; index++) {
                    MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
                    dictionary[index] = borrowedUtf8String(data, lengths[index]);
                }
                String[] out = new String[count];
                for (int index = 0; index < count; index++) {
                    out[index] = dictionary[indices[index]];
                }
                return out;
            }

            MemorySegment stringDataArray = (MemorySegment) columnBatchStringDataArray.invoke(raw);
            MemorySegment stringLengthsData = (MemorySegment) columnBatchStringLengthsData.invoke(raw);
            if (isNull(stringDataArray) || isNull(stringLengthsData)) return new String[0];
            MemorySegment dataArray = stringDataArray.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
            int[] lengths = stringLengthsData.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
            String[] out = new String[count];
            for (int index = 0; index < count; index++) {
                MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
                out[index] = borrowedUtf8String(data, lengths[index]);
            }
            return out;
        }

        private String[] columnBatchSecondStrings(MemorySegment raw, int count) throws Throwable {
            if (count == 0) return new String[0];
            MemorySegment stringDataArray = (MemorySegment) columnBatchSecondStringDataArray.invoke(raw);
            MemorySegment stringLengthsData = (MemorySegment) columnBatchSecondStringLengthsData.invoke(raw);
            if (isNull(stringDataArray) || isNull(stringLengthsData)) return new String[0];
            MemorySegment dataArray = stringDataArray.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
            int[] lengths = stringLengthsData.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
            String[] out = new String[count];
            for (int index = 0; index < count; index++) {
                MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
                out[index] = borrowedUtf8String(data, lengths[index]);
            }
            return out;
        }

        private String[] columnBatchStringColumn(MemorySegment raw, int column, int count) throws Throwable {
            if (count == 0) return new String[0];
            MemorySegment stringDataArray = (MemorySegment) columnBatchColumnStringDataArray.invoke(raw, column);
            MemorySegment stringLengthsData = (MemorySegment) columnBatchColumnStringLengthsData.invoke(raw, column);
            if (isNull(stringDataArray) || isNull(stringLengthsData)) return new String[0];
            MemorySegment dataArray = stringDataArray.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
            int[] lengths = stringLengthsData.reinterpret((long) count * Integer.BYTES).toArray(ValueLayout.JAVA_INT);
            String[] out = new String[count];
            for (int index = 0; index < count; index++) {
                MemorySegment data = dataArray.get(ValueLayout.ADDRESS, (long) index * ValueLayout.ADDRESS.byteSize());
                out[index] = borrowedUtf8String(data, lengths[index]);
            }
            return out;
        }

        private Object[] mixedColumn(MemorySegment raw, int column, int count) throws Throwable {
            int[] valueKinds = intColumn((MemorySegment) columnBatchColumnValueKindsData.invoke(raw, column), count);
            if (valueKinds.length != count) return null;

            long[] entities = longColumn((MemorySegment) columnBatchColumnEntitiesData.invoke(raw, column), count);
            long[] ints = longColumn((MemorySegment) columnBatchColumnIntsData.invoke(raw, column), count);
            double[] floats = doubleColumn((MemorySegment) columnBatchColumnFloatsData.invoke(raw, column), count);
            boolean[] bools = boolColumn((MemorySegment) columnBatchColumnBoolsData.invoke(raw, column), count);
            String[] strings = columnBatchStringColumn(raw, column, count);

            Object[] out = new Object[count];
            for (int row = 0; row < count; row++) {
                out[row] = switch (valueKinds[row]) {
                    case 0 -> null;
                    case 1 -> new Entity(entities[row]);
                    case 2 -> strings[row];
                    case 3 -> ints[row];
                    case 4 -> floats[row];
                    case 5 -> bools[row];
                    case 6 -> new Keyword(strings[row]);
                    case 7 -> new Symbol(strings[row]);
                    case 10 -> UUID.fromString(strings[row]);
                    case 12 -> new Date(ints[row]);
                    default -> strings[row];
                };
            }
            return out;
        }

        private Object[] valueColumn(MemorySegment raw, int column, int count) throws Throwable {
            if (count == 0) return new Object[0];
            MemorySegment valuesData = (MemorySegment) columnBatchColumnValuesData.invoke(raw, column);
            if (isNull(valuesData)) return null;
            MemorySegment valueArray = valuesData.reinterpret((long) count * ValueLayout.ADDRESS.byteSize());
            Object[] out = new Object[count];
            for (int row = 0; row < count; row++) {
                MemorySegment value = valueArray.get(ValueLayout.ADDRESS, (long) row * ValueLayout.ADDRESS.byteSize());
                out[row] = valueToJava(value);
            }
            return out;
        }

        public ColumnResult queryColumns(PreparedQuery query, String inputs) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) queryDbPreparedColumnBatchWithInputs.invoke(
                    handle.raw,
                    query.raw,
                    local.allocateUtf8String(inputs));
                return columnResultFromBatch(raw);
            }
        }

        public ColumnResult queryColumns(Statement stmt) throws Throwable {
            requireOpen();
            stmt.requireOpen();
            return columnResultFromBatch((MemorySegment) queryDbStmtColumnBatch.invoke(handle.raw, stmt.raw));
        }

        private ColumnResult columnResultFromBatch(MemorySegment raw) throws Throwable {
            if (isNull(raw)) return null;
            try {
                int count = (int) columnBatchCount.invoke(raw);
                int columnCount = (int) columnBatchColumnCount.invoke(raw);
                if (columnCount <= 0) return null;
                int[] kinds = new int[columnCount];
                Object[] columns = new Object[columnCount];
                for (int column = 0; column < columnCount; column++) {
                    int kind = (int) columnBatchColumnKind.invoke(raw, column);
                    kinds[column] = kind;
                    columns[column] = switch (kind) {
                        case COLUMN_ENTITY -> longColumn(
                            (MemorySegment) columnBatchColumnEntitiesData.invoke(raw, column),
                            count);
                        case COLUMN_STRING, COLUMN_KEYWORD, COLUMN_SYMBOL, COLUMN_UUID ->
                            columnBatchStringColumn(raw, column, count);
                        case COLUMN_INT -> longColumn(
                            (MemorySegment) columnBatchColumnIntsData.invoke(raw, column),
                            count);
                        case COLUMN_INSTANT -> longColumn(
                            (MemorySegment) columnBatchColumnIntsData.invoke(raw, column),
                            count);
                        case COLUMN_BOOL -> boolColumn(
                            (MemorySegment) columnBatchColumnBoolsData.invoke(raw, column),
                            count);
                        case COLUMN_FLOAT -> doubleColumn(
                            (MemorySegment) columnBatchColumnFloatsData.invoke(raw, column),
                            count);
                        case COLUMN_MIXED -> mixedColumn(raw, column, count);
                        case COLUMN_VALUE -> valueColumn(raw, column, count);
                        default -> null;
                    };
                    if (columns[column] == null) return null;
                }
                return new ColumnResult(count, kinds, columns);
            } finally {
                columnBatchFree.invoke(raw);
            }
        }

        public ResultSet query(Statement stmt) throws Throwable {
            requireOpen();
            return new ResultSet((MemorySegment) queryDbStmtResult.invoke(handle.raw, stmt.raw));
        }

        public String with(String tx) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return ownedString((MemorySegment) withEdn.invoke(handle.raw, local.allocateUtf8String(tx)));
            }
        }

        public TxReport withReport(String tx) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new TxReport((MemorySegment) withEdnReport.invoke(handle.raw, local.allocateUtf8String(tx)));
            }
        }

        public TxReport withReport(String tx, TxFunctionRegistry registry) throws Throwable {
            requireOpen();
            registry.requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return new TxReport((MemorySegment) withEdnReportWithTxFns.invoke(
                    handle.raw,
                    local.allocateUtf8String(tx),
                    registry.raw));
            }
        }

        public DB dbWith(String tx) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment db = (MemorySegment) dbWithEdn.invoke(handle.raw, local.allocateUtf8String(tx));
                if (isNull(db)) throw new IllegalStateException("failed to create DB snapshot");
                return new DB(db);
            }
        }

        public DB dbWith(TxBuilder tx) throws Throwable {
            requireOpen();
            tx.requireOpen();
            MemorySegment db = (MemorySegment) txDbWith.invoke(handle.raw, tx.raw);
            if (isNull(db)) throw new IllegalStateException("failed to create DB snapshot");
            return new DB(db);
        }

        public Object pull(String pattern, long entity) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle value = new ValueHandle((MemorySegment) pullEdn.invoke(
                     handle.raw,
                     local.allocateUtf8String(pattern),
                     entity))) {
                return value.value();
            }
        }

        public Object pull(PreparedPullPattern pattern, long entity) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (ValueHandle value = new ValueHandle((MemorySegment) pullPrepared.invoke(
                     handle.raw,
                     pattern.raw,
                     entity))) {
                return value.value();
            }
        }

        public Object pullLookupRefString(String pattern, String attr, String value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefStringEdn.invoke(
                     handle.raw,
                     local.allocateUtf8String(pattern),
                     local.allocateUtf8String(attr),
                     local.allocateUtf8String(value)))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefString(PreparedPullPattern pattern, String attr, String value) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefStringPrepared.invoke(
                     handle.raw,
                     pattern.raw,
                     local.allocateUtf8String(attr),
                     local.allocateUtf8String(value)))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefKeyword(String pattern, String attr, String value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefKeywordEdn.invoke(
                     handle.raw,
                     local.allocateUtf8String(pattern),
                     local.allocateUtf8String(attr),
                     local.allocateUtf8String(value)))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefKeyword(PreparedPullPattern pattern, String attr, String value) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefKeywordPrepared.invoke(
                     handle.raw,
                     pattern.raw,
                     local.allocateUtf8String(attr),
                     local.allocateUtf8String(value)))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefUuid(String pattern, String attr, UUID value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefUuidEdn.invoke(
                     handle.raw,
                     local.allocateUtf8String(pattern),
                     local.allocateUtf8String(attr),
                     local.allocateUtf8String(value.toString())))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefUuid(PreparedPullPattern pattern, String attr, UUID value) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefUuidPrepared.invoke(
                     handle.raw,
                     pattern.raw,
                     local.allocateUtf8String(attr),
                     local.allocateUtf8String(value.toString())))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefEntity(String pattern, String attr, long value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefEntityEdn.invoke(
                     handle.raw,
                     local.allocateUtf8String(pattern),
                     local.allocateUtf8String(attr),
                     value))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefEntity(PreparedPullPattern pattern, String attr, long value) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefEntityPrepared.invoke(
                     handle.raw,
                     pattern.raw,
                     local.allocateUtf8String(attr),
                     value))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefInt(String pattern, String attr, long value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefIntEdn.invoke(
                     handle.raw,
                     local.allocateUtf8String(pattern),
                     local.allocateUtf8String(attr),
                     value))) {
                return pulled.value();
            }
        }

        public Object pullLookupRefInt(PreparedPullPattern pattern, String attr, long value) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle pulled = new ValueHandle((MemorySegment) pullLookupRefIntPrepared.invoke(
                     handle.raw,
                     pattern.raw,
                     local.allocateUtf8String(attr),
                     value))) {
                return pulled.value();
            }
        }

        public Object pullMany(String pattern, long... entities) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle value = new ValueHandle((MemorySegment) pullManyEdn.invoke(
                     handle.raw,
                     local.allocateUtf8String(pattern),
                     longArray(local, entities),
                     entities.length))) {
                return value.value();
            }
        }

        public Object pullMany(PreparedPullPattern pattern, long... entities) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle value = new ValueHandle((MemorySegment) pullManyPrepared.invoke(
                     handle.raw,
                     pattern.raw,
                     longArray(local, entities),
                     entities.length))) {
                return value.value();
            }
        }

        public Object pullManyLookupRefString(String pattern, String attr, String... values) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment array = local.allocateArray(ValueLayout.ADDRESS, values.length);
                for (int i = 0; i < values.length; i++) {
                    array.setAtIndex(ValueLayout.ADDRESS, i, local.allocateUtf8String(values[i]));
                }
                try (ValueHandle value = new ValueHandle((MemorySegment) pullManyLookupRefStringEdn.invoke(
                         handle.raw,
                         local.allocateUtf8String(pattern),
                         local.allocateUtf8String(attr),
                         array,
                         values.length))) {
                    return value.value();
                }
            }
        }

        public Object pullManyLookupRefString(PreparedPullPattern pattern, String attr, String... values) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment array = local.allocateArray(ValueLayout.ADDRESS, values.length);
                for (int i = 0; i < values.length; i++) {
                    array.setAtIndex(ValueLayout.ADDRESS, i, local.allocateUtf8String(values[i]));
                }
                try (ValueHandle value = new ValueHandle((MemorySegment) pullManyLookupRefStringPrepared.invoke(
                         handle.raw,
                         pattern.raw,
                         local.allocateUtf8String(attr),
                         array,
                         values.length))) {
                    return value.value();
                }
            }
        }

        public Object pullManyLookupRefUuid(String pattern, String attr, UUID... values) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment array = local.allocateArray(ValueLayout.ADDRESS, values.length);
                for (int i = 0; i < values.length; i++) {
                    array.setAtIndex(ValueLayout.ADDRESS, i, local.allocateUtf8String(values[i].toString()));
                }
                try (ValueHandle value = new ValueHandle((MemorySegment) pullManyLookupRefUuidEdn.invoke(
                         handle.raw,
                         local.allocateUtf8String(pattern),
                         local.allocateUtf8String(attr),
                         array,
                         values.length))) {
                    return value.value();
                }
            }
        }

        public Object pullManyLookupRefUuid(PreparedPullPattern pattern, String attr, UUID... values) throws Throwable {
            requireOpen();
            pattern.requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment array = local.allocateArray(ValueLayout.ADDRESS, values.length);
                for (int i = 0; i < values.length; i++) {
                    array.setAtIndex(ValueLayout.ADDRESS, i, local.allocateUtf8String(values[i].toString()));
                }
                try (ValueHandle value = new ValueHandle((MemorySegment) pullManyLookupRefUuidPrepared.invoke(
                         handle.raw,
                         pattern.raw,
                         local.allocateUtf8String(attr),
                         array,
                         values.length))) {
                    return value.value();
                }
            }
        }

        private void requireOpen() {
            if (isNull(handle.raw)) throw new IllegalStateException("DB snapshot is closed");
        }

        @Override
        public void close() {
            cleanable.clean();
        }
    }

    public final class EntityView implements AutoCloseable {
        private final NativeHandle handle;
        private final Cleaner.Cleanable cleanable;

        private EntityView(MemorySegment raw) {
            this.handle = new NativeHandle(entityFree, raw);
            this.cleanable = CLEANER.register(this, handle);
        }

        public boolean found() throws Throwable {
            requireOpen();
            return (boolean) entityFound.invoke(handle.raw);
        }

        public long id() throws Throwable {
            requireOpen();
            return (long) entityId.invoke(handle.raw);
        }

        public boolean contains(String attr) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                return (boolean) entityContains.invoke(handle.raw, local.allocateUtf8String(attr));
            }
        }

        public Object get(String attr) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle value = new ValueHandle((MemorySegment) entityGet.invoke(
                     handle.raw,
                     local.allocateUtf8String(attr)))) {
                return value.value();
            }
        }

        public Object values(String attr) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined();
                 ValueHandle value = new ValueHandle((MemorySegment) entityValues.invoke(
                     handle.raw,
                     local.allocateUtf8String(attr)))) {
                return value.value();
            }
        }

        public EntityView ref(String attr) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) entityRef.invoke(handle.raw, local.allocateUtf8String(attr));
                if (isNull(raw)) throw new IllegalStateException("failed to create referenced entity view");
                return new EntityView(raw);
            }
        }

        public long[] refs(String attr) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                MemorySegment raw = (MemorySegment) entityRefs.invoke(handle.raw, local.allocateUtf8String(attr));
                if (isNull(raw)) return null;
                try {
                    int count = (int) u64ArrayCount.invoke(raw);
                    if (count == 0) return new long[0];
                    MemorySegment data = (MemorySegment) u64ArrayData.invoke(raw);
                    if (isNull(data)) return new long[0];
                    return data.reinterpret((long) count * Long.BYTES).toArray(ValueLayout.JAVA_LONG);
                } finally {
                    u64ArrayFree.invoke(raw);
                }
            }
        }

        public Object touch() throws Throwable {
            requireOpen();
            try (ValueHandle value = new ValueHandle((MemorySegment) entityTouch.invoke(handle.raw))) {
                return value.value();
            }
        }

        private void requireOpen() {
            if (isNull(handle.raw)) throw new IllegalStateException("entity view is closed");
        }

        @Override
        public void close() {
            cleanable.clean();
        }
    }

    public final class ValueHandle implements AutoCloseable {
        private MemorySegment raw;

        private ValueHandle(MemorySegment raw) {
            if (isNull(raw)) throw new IllegalStateException("value handle is null");
            this.raw = raw;
        }

        public Object value() throws Throwable {
            requireOpen();
            return valueToJava((MemorySegment) valueHandleValue.invoke(raw));
        }

        public String edn() throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) valueHandleEdn.invoke(raw));
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("value handle is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(valueHandleFree, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class PreparedQuery implements AutoCloseable {
        private MemorySegment raw;

        private PreparedQuery(MemorySegment raw) {
            this.raw = raw;
        }

        public Statement statement() throws Throwable {
            requireOpen();
            MemorySegment stmt = (MemorySegment) stmtCreate.invoke(raw);
            if (isNull(stmt)) throw new IllegalStateException("failed to create statement");
            return new Statement(stmt);
        }

        public String edn() throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) preparedQueryEdn.invoke(raw));
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("prepared query is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(preparedQueryFree, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class PreparedPullPattern implements AutoCloseable {
        private MemorySegment raw;

        private PreparedPullPattern(MemorySegment raw) {
            this.raw = raw;
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("prepared pull pattern is closed");
        }

        public String edn() throws Throwable {
            requireOpen();
            return ownedString((MemorySegment) preparedPullPatternEdn.invoke(raw));
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(preparedPullPatternFree, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class TxBuilder implements AutoCloseable {
        private MemorySegment raw;

        private TxBuilder(MemorySegment raw) {
            this.raw = raw;
        }

        public TxBuilder addString(long e, String attr, String value) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                boolean ok = (boolean) txAddString.invoke(raw, e, local.allocateUtf8String(attr), local.allocateUtf8String(value));
                if (!ok) throw new IllegalStateException("failed to add string tx datom");
                return this;
            }
        }

        public TxBuilder addKeyword(long e, String attr, String value) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                boolean ok = (boolean) txAddKeyword.invoke(raw, e, local.allocateUtf8String(attr), local.allocateUtf8String(value));
                if (!ok) throw new IllegalStateException("failed to add keyword tx datom");
                return this;
            }
        }

        public TxBuilder addSymbol(long e, String attr, String value) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                boolean ok = (boolean) txAddSymbol.invoke(raw, e, local.allocateUtf8String(attr), local.allocateUtf8String(value));
                if (!ok) throw new IllegalStateException("failed to add symbol tx datom");
                return this;
            }
        }

        public TxBuilder addEntity(long e, String attr, long value) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                boolean ok = (boolean) txAddEntity.invoke(raw, e, local.allocateUtf8String(attr), value);
                if (!ok) throw new IllegalStateException("failed to add entity tx datom");
                return this;
            }
        }

        public TxBuilder addInt(long e, String attr, long value) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                boolean ok = (boolean) txAddInt.invoke(raw, e, local.allocateUtf8String(attr), value);
                if (!ok) throw new IllegalStateException("failed to add int tx datom");
                return this;
            }
        }

        public TxBuilder addBool(long e, String attr, boolean value) throws Throwable {
            try (Arena local = Arena.ofConfined()) {
                boolean ok = (boolean) txAddBool.invoke(raw, e, local.allocateUtf8String(attr), value);
                if (!ok) throw new IllegalStateException("failed to add bool tx datom");
                return this;
            }
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("transaction builder is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(txFree, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class Statement implements AutoCloseable {
        private MemorySegment raw;

        private Statement(MemorySegment raw) {
            this.raw = raw;
        }

        public Statement bindString(String value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                stmtClear.invoke(raw);
                boolean ok = (boolean) stmtBindString.invoke(raw, local.allocateUtf8String(value));
                if (!ok) throw new IllegalStateException("failed to bind string");
                return this;
            }
        }

        public Statement bindStringCollection(String... values) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                stmtClear.invoke(raw);
                MemorySegment array = local.allocateArray(ValueLayout.ADDRESS, values.length);
                for (int i = 0; i < values.length; i++) {
                    array.setAtIndex(ValueLayout.ADDRESS, i, local.allocateUtf8String(values[i]));
                }
                boolean ok = (boolean) stmtBindStringCollection.invoke(raw, array, values.length);
                if (!ok) throw new IllegalStateException("failed to bind string collection");
                return this;
            }
        }

        public Statement bindPullPatternAndString(String pattern, String value) throws Throwable {
            requireOpen();
            try (Arena local = Arena.ofConfined()) {
                stmtClear.invoke(raw);
                boolean ok = (boolean) stmtBindPullPatternEdn.invoke(raw, local.allocateUtf8String(pattern));
                ok = ok && (boolean) stmtBindString.invoke(raw, local.allocateUtf8String(value));
                if (!ok) throw new IllegalStateException("failed to bind pull pattern and string");
                return this;
            }
        }

        private void requireOpen() {
            if (isNull(raw)) throw new IllegalStateException("statement is closed");
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(stmtFree, raw);
                raw = MemorySegment.NULL;
            }
        }
    }

    public final class ResultSet implements AutoCloseable {
        private MemorySegment raw;

        private ResultSet(MemorySegment raw) throws Throwable {
            if (isNull(raw)) throw new IllegalStateException("query returned null result");
            if (!((boolean) resultOk.invoke(raw))) {
                String error = ownedString((MemorySegment) resultError.invoke(raw));
                resultFree.invoke(raw);
                throw new IllegalStateException(error);
            }
            this.raw = raw;
        }

        public int rowCount() throws Throwable {
            return (int) resultRowCount.invoke(raw);
        }

        public long[] singleEntityColumn() throws Throwable {
            int rowCount = rowCount();
            if (rowCount == 0) return new long[0];
            if ((int) resultValueCount.invoke(raw, 0) != 1
                    || (int) resultPullCount.invoke(raw, 0) != 0
                    || (int) resultValueKind.invoke(raw, 0, 0) != 1) {
                return null;
            }
            long[] out = new long[rowCount];
            for (int row = 0; row < rowCount; row++) {
                out[row] = (long) resultValueEntity.invoke(raw, row, 0);
            }
            return out;
        }

        public List<List<Object>> rows() throws Throwable {
            int rowCount = rowCount();
            List<List<Object>> rows = new ArrayList<>(rowCount);
            long[] entityColumn = singleEntityColumn();
            if (entityColumn != null && rowCount > 0) {
                for (long entity : entityColumn) {
                    List<Object> values = new ArrayList<>(1);
                    values.add(new Entity(entity));
                    rows.add(values);
                }
                return rows;
            }
            for (int row = 0; row < rowCount; row++) {
                List<Object> values = new ArrayList<>();
                int valueCount = (int) resultValueCount.invoke(raw, row);
                for (int column = 0; column < valueCount; column++) {
                    int kind = (int) resultValueKind.invoke(raw, row, column);
                    values.add(resultValueToJava(raw, row, column, kind));
                }
                int pullCount = (int) resultPullCount.invoke(raw, row);
                for (int pull = 0; pull < pullCount; pull++) {
                    values.add(valueToJava((MemorySegment) resultPull.invoke(raw, row, pull)));
                }
                rows.add(values);
            }
            return rows;
        }

        public Object scalar() throws Throwable {
            List<List<Object>> rows = rows();
            if (rows.size() != 1 || rows.get(0).size() != 1) {
                throw new IllegalStateException("expected one scalar result, got " + rows);
            }
            return rows.get(0).get(0);
        }

        @Override
        public void close() {
            if (!isNull(raw)) {
                closeHandle(resultFree, raw);
                raw = MemorySegment.NULL;
            }
        }
    }
}
