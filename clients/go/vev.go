// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

/*
#cgo CFLAGS: -I${SRCDIR}/../../include
#cgo darwin LDFLAGS: -L${SRCDIR}/../../build/lib -lvev -Wl,-rpath,${SRCDIR}/../../build/lib
#cgo linux LDFLAGS: -L${SRCDIR}/../../build/lib -lvev -Wl,-rpath,${SRCDIR}/../../build/lib
#cgo windows LDFLAGS: -L${SRCDIR}/../../build/lib -lvev
#include "vev.h"
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"os"
	"reflect"
	"sort"
	"strings"
	"time"
	"unsafe"
)

func cstring(text string) *C.char {
	return C.CString(text)
}

func ownedString(ptr *C.char) string {
	if ptr == nil {
		return ""
	}
	defer C.vev_string_free(ptr)
	return C.GoString(ptr)
}

type Conn struct {
	raw C.vev_conn_t
}

func CreateConn() (*Conn, error) {
	raw := C.vev_conn_open_memory()
	if raw == nil {
		return nil, fmt.Errorf("failed to open Vev connection")
	}
	return &Conn{raw: raw}, nil
}

func OpenMemory() (*Conn, error) {
	return CreateConn()
}

func ConnFromDB(db *DB) (*Conn, error) {
	// Resident/in-memory compatibility only. Durable DB handles are immutable
	// values and should be queried directly.
	raw := C.vev_conn_from_db(db.raw)
	if raw == nil {
		return nil, fmt.Errorf("failed to create connection from DB snapshot")
	}
	return &Conn{raw: raw}, nil
}

func (c *Conn) Close() {
	if c.raw != nil {
		C.vev_conn_close(c.raw)
		c.raw = nil
	}
}

func (c *Conn) Transact(tx string) string {
	txText := cstring(tx)
	defer C.free(unsafe.Pointer(txText))
	return ownedString(C.vev_transact_edn(c.raw, txText))
}

func (c *Conn) QueryText(query string, inputs string) string {
	queryText := cstring(query)
	inputsText := cstring(inputs)
	defer C.free(unsafe.Pointer(queryText))
	defer C.free(unsafe.Pointer(inputsText))
	return ownedString(C.vev_query_edn_with_inputs(c.raw, queryText, inputsText))
}

func (c *Conn) Q(queryText string, inputs string) (*ResultSet, error) {
	db, err := c.DB()
	if err != nil {
		return nil, err
	}
	defer db.Close()
	return db.Q(queryText, inputs)
}

func (c *Conn) DB() (*DB, error) {
	raw := C.vev_conn_db(c.raw)
	if raw == nil {
		return nil, fmt.Errorf("failed to retain DB snapshot")
	}
	return &DB{raw: raw}, nil
}

type DurableConn struct {
	raw C.vev_connection_t
}

func Connect(uri string) (*DurableConn, error) {
	uriText := cstring(uri)
	defer C.free(unsafe.Pointer(uriText))
	raw := C.vev_connect(uriText)
	if raw == nil {
		return nil, fmt.Errorf("failed to connect Vev durable connection")
	}
	if !bool(C.vev_connection_ok(raw)) {
		err := ownedString(C.vev_connection_error(raw))
		C.vev_connection_close(raw)
		return nil, fmt.Errorf("%s", err)
	}
	return &DurableConn{raw: raw}, nil
}

func (c *DurableConn) Close() {
	if c.raw != nil {
		C.vev_connection_close(c.raw)
		c.raw = nil
	}
}

func (c *DurableConn) Backend() string {
	return ownedString(C.vev_connection_backend(c.raw))
}

func (c *DurableConn) Path() string {
	return ownedString(C.vev_connection_path(c.raw))
}

func (c *DurableConn) BasisT() uint64 {
	return uint64(C.vev_connection_basis_t(c.raw))
}

func (c *DurableConn) TxCount() uint64 {
	return uint64(C.vev_connection_tx_count(c.raw))
}

func (c *DurableConn) InfoEDN() string {
	return ownedString(C.vev_connection_info_edn(c.raw))
}

func (c *DurableConn) Transact(tx string) (*TxReport, error) {
	txText := cstring(tx)
	defer C.free(unsafe.Pointer(txText))
	raw := C.vev_connection_transact_edn_report(c.raw, txText)
	if raw == nil {
		return nil, fmt.Errorf("failed to transact durable connection")
	}
	return &TxReport{raw: raw}, nil
}

func (c *DurableConn) TransactBulk(builders []*TxBuilder) (*TxReport, error) {
	if len(builders) == 0 {
		return nil, fmt.Errorf("transact bulk requires at least one builder")
	}
	raw, freeRaw, err := rawTxBuilderArray(builders, false)
	if err != nil {
		return nil, err
	}
	defer freeRaw()
	report := C.vev_connection_tx_commit_many_report(c.raw, raw, C.int(len(builders)))
	if report == nil {
		return nil, fmt.Errorf("failed to transact bulk tx builders")
	}
	return &TxReport{raw: report}, nil
}

func (c *DurableConn) TransactLogicalBulk(builders []*TxBuilder) (*TxReportArray, error) {
	raw, freeRaw, err := rawTxBuilderArray(builders, true)
	if err != nil {
		return nil, err
	}
	defer freeRaw()
	reports := C.vev_connection_tx_commit_logical_many_reports(c.raw, raw, C.int(len(builders)))
	if reports == nil {
		return nil, fmt.Errorf("failed to logical-group transact tx builders")
	}
	return &TxReportArray{raw: reports}, nil
}

func (c *DurableConn) TransactLogical(txTexts []string) (*TxReportArray, error) {
	raw, freeRaw, err := rawCStringArray(txTexts)
	if err != nil {
		return nil, err
	}
	defer freeRaw()
	reports := C.vev_connection_transact_many_edn_reports(c.raw, raw, C.int(len(txTexts)))
	if reports == nil {
		return nil, fmt.Errorf("failed to logical-group transact EDN tx data")
	}
	return &TxReportArray{raw: reports}, nil
}

func (c *DurableConn) DB() (*DB, error) {
	raw := C.vev_connection_db(c.raw)
	if raw == nil {
		return nil, fmt.Errorf("failed to retain durable DB snapshot")
	}
	return &DB{raw: raw}, nil
}

func (c *DurableConn) Q(queryText string, inputs string) (*ResultSet, error) {
	db, err := c.DB()
	if err != nil {
		return nil, err
	}
	defer db.Close()
	return db.Q(queryText, inputs)
}

type TxBuilder struct {
	raw C.vev_tx_builder_t
}

func NewTxBuilder(capacity int) (*TxBuilder, error) {
	raw := C.vev_tx_create(C.int(capacity))
	if raw == nil {
		return nil, fmt.Errorf("failed to create transaction builder")
	}
	return &TxBuilder{raw: raw}, nil
}

func (b *TxBuilder) Close() {
	if b.raw != nil {
		C.vev_tx_free(b.raw)
		b.raw = nil
	}
}

func (b *TxBuilder) AddString(entity uint64, attr string, value string) error {
	attrText := cstring(attr)
	valueText := cstring(value)
	defer C.free(unsafe.Pointer(attrText))
	defer C.free(unsafe.Pointer(valueText))
	if !bool(C.vev_tx_add_string(b.raw, C.ulonglong(entity), attrText, valueText)) {
		return fmt.Errorf("failed to add string datom to transaction builder")
	}
	return nil
}

func (b *TxBuilder) AddKeyword(entity uint64, attr string, value string) error {
	attrText := cstring(attr)
	valueText := cstring(value)
	defer C.free(unsafe.Pointer(attrText))
	defer C.free(unsafe.Pointer(valueText))
	if !bool(C.vev_tx_add_keyword(b.raw, C.ulonglong(entity), attrText, valueText)) {
		return fmt.Errorf("failed to add keyword datom to transaction builder")
	}
	return nil
}

func (b *TxBuilder) AddSymbol(entity uint64, attr string, value string) error {
	attrText := cstring(attr)
	valueText := cstring(value)
	defer C.free(unsafe.Pointer(attrText))
	defer C.free(unsafe.Pointer(valueText))
	if !bool(C.vev_tx_add_symbol(b.raw, C.ulonglong(entity), attrText, valueText)) {
		return fmt.Errorf("failed to add symbol datom to transaction builder")
	}
	return nil
}

func (b *TxBuilder) AddEntity(entity uint64, attr string, value uint64) error {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	if !bool(C.vev_tx_add_entity(b.raw, C.ulonglong(entity), attrText, C.ulonglong(value))) {
		return fmt.Errorf("failed to add entity datom to transaction builder")
	}
	return nil
}

func (b *TxBuilder) AddInt(entity uint64, attr string, value int64) error {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	if !bool(C.vev_tx_add_int(b.raw, C.ulonglong(entity), attrText, C.longlong(value))) {
		return fmt.Errorf("failed to add int datom to transaction builder")
	}
	return nil
}

func (b *TxBuilder) AddBool(entity uint64, attr string, value bool) error {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	if !bool(C.vev_tx_add_bool(b.raw, C.ulonglong(entity), attrText, C.bool(value))) {
		return fmt.Errorf("failed to add bool datom to transaction builder")
	}
	return nil
}

func rawTxBuilderArray(builders []*TxBuilder, allowEmpty bool) (*C.vev_tx_builder_t, func(), error) {
	if len(builders) == 0 {
		if allowEmpty {
			return nil, func() {}, nil
		}
		return nil, func() {}, fmt.Errorf("transaction builder array cannot be empty")
	}
	bytes := C.size_t(len(builders)) * C.size_t(unsafe.Sizeof(C.vev_tx_builder_t(nil)))
	raw := C.malloc(bytes)
	if raw == nil {
		return nil, func() {}, fmt.Errorf("failed to allocate transaction builder array")
	}
	values := unsafe.Slice((*C.vev_tx_builder_t)(raw), len(builders))
	for index, builder := range builders {
		if builder == nil || builder.raw == nil {
			C.free(raw)
			return nil, func() {}, fmt.Errorf("transaction builder %d is nil or closed", index)
		}
		values[index] = builder.raw
	}
	return (*C.vev_tx_builder_t)(raw), func() { C.free(raw) }, nil
}

func rawCStringArray(texts []string) (**C.char, func(), error) {
	if len(texts) == 0 {
		return nil, func() {}, nil
	}
	bytes := C.size_t(len(texts)) * C.size_t(unsafe.Sizeof((*C.char)(nil)))
	raw := C.malloc(bytes)
	if raw == nil {
		return nil, func() {}, fmt.Errorf("failed to allocate C string array")
	}
	values := unsafe.Slice((**C.char)(raw), len(texts))
	for index, text := range texts {
		values[index] = cstring(text)
	}
	return (**C.char)(raw), func() {
		for _, value := range values {
			C.free(unsafe.Pointer(value))
		}
		C.free(raw)
	}, nil
}

type DB struct {
	raw C.vev_db_t
}

func (db *DB) Close() {
	if db.raw != nil {
		C.vev_db_release(db.raw)
		db.raw = nil
	}
}

func (db *DB) QueryPrepared(query *PreparedQuery, inputs string) string {
	inputsText := cstring(inputs)
	defer C.free(unsafe.Pointer(inputsText))
	return ownedString(C.vev_query_db_prepared_with_inputs(db.raw, query.raw, inputsText))
}

func (db *DB) QueryText(queryText string, inputs string) (string, error) {
	query, err := Prepare(queryText)
	if err != nil {
		return "", err
	}
	defer query.Close()
	return db.QueryPrepared(query, inputs), nil
}

func (db *DB) Q(queryText string, inputs string) (*ResultSet, error) {
	query, err := Prepare(queryText)
	if err != nil {
		return nil, err
	}
	defer query.Close()
	return db.QueryRows(query, inputs)
}

func (db *DB) QueryRows(query *PreparedQuery, inputs string) (*ResultSet, error) {
	inputsText := cstring(inputs)
	defer C.free(unsafe.Pointer(inputsText))
	raw := C.vev_query_db_prepared_result_with_inputs(db.raw, query.raw, inputsText)
	return newResultSet(raw)
}

func (db *DB) Entity(entity uint64) (*EntityView, error) {
	raw := C.vev_db_entity(db.raw, C.ulonglong(entity))
	if raw == nil {
		return nil, fmt.Errorf("failed to create entity view")
	}
	return &EntityView{raw: raw}, nil
}

func (db *DB) EntityLookupRefString(attr string, value string) (*EntityView, error) {
	attrText := cstring(attr)
	valueText := cstring(value)
	defer C.free(unsafe.Pointer(attrText))
	defer C.free(unsafe.Pointer(valueText))
	raw := C.vev_db_entity_lookup_ref_string(db.raw, attrText, valueText)
	if raw == nil {
		return nil, fmt.Errorf("failed to create lookup-ref entity view")
	}
	return &EntityView{raw: raw}, nil
}

func (db *DB) EntityIdent(ident string) (*EntityView, error) {
	identText := cstring(ident)
	defer C.free(unsafe.Pointer(identText))
	raw := C.vev_db_entity_ident(db.raw, identText)
	if raw == nil {
		return nil, fmt.Errorf("failed to create ident entity view")
	}
	return &EntityView{raw: raw}, nil
}

func (db *DB) QueryColumns(query *PreparedQuery, inputs string) (*ColumnResult, error) {
	inputsText := cstring(inputs)
	defer C.free(unsafe.Pointer(inputsText))
	raw := C.vev_query_db_prepared_column_batch_with_inputs(db.raw, query.raw, inputsText)
	return columnResultFromRaw(raw)
}

func (db *DB) QueryStatementRows(stmt *Statement) (*ResultSet, error) {
	raw := C.vev_query_db_stmt_result(db.raw, stmt.raw)
	return newResultSet(raw)
}

func (db *DB) QueryStatementColumns(stmt *Statement) (*ColumnResult, error) {
	raw := C.vev_query_db_stmt_column_batch(db.raw, stmt.raw)
	return columnResultFromRaw(raw)
}

func columnResultFromRaw(raw C.vev_column_batch_t) (*ColumnResult, error) {
	if raw == nil {
		return nil, nil
	}
	defer C.vev_column_batch_free(raw)

	count := int(C.vev_column_batch_count(raw))
	switch C.vev_column_batch_kind(raw) {
	case C.VEV_COLUMN_BATCH_ENTITY:
		return &ColumnResult{
			Count:   count,
			Kinds:   []int{ColumnEntity},
			Columns: []any{entityColumn(C.vev_column_batch_entities_data(raw), count)},
		}, nil
	case C.VEV_COLUMN_BATCH_STRING:
		return &ColumnResult{
			Count:   count,
			Kinds:   []int{ColumnString},
			Columns: []any{stringColumn(raw, count)},
		}, nil
	case C.VEV_COLUMN_BATCH_INT:
		return &ColumnResult{
			Count:   count,
			Kinds:   []int{ColumnInt},
			Columns: []any{intColumn(C.vev_column_batch_ints_data(raw), count)},
		}, nil
	case C.VEV_COLUMN_BATCH_ENTITY_INT:
		return &ColumnResult{
			Count: count,
			Kinds: []int{ColumnEntity, ColumnInt},
			Columns: []any{
				entityColumn(C.vev_column_batch_entities_data(raw), count),
				intColumn(C.vev_column_batch_ints_data(raw), count),
			},
		}, nil
	case C.VEV_COLUMN_BATCH_ENTITY_STRING:
		return &ColumnResult{
			Count: count,
			Kinds: []int{ColumnEntity, ColumnString},
			Columns: []any{
				entityColumn(C.vev_column_batch_entities_data(raw), count),
				stringColumn(raw, count),
			},
		}, nil
	case C.VEV_COLUMN_BATCH_STRING_INT:
		return &ColumnResult{
			Count: count,
			Kinds: []int{ColumnString, ColumnInt},
			Columns: []any{
				stringColumn(raw, count),
				intColumn(C.vev_column_batch_ints_data(raw), count),
			},
		}, nil
	case C.VEV_COLUMN_BATCH_STRING_STRING:
		return &ColumnResult{
			Count: count,
			Kinds: []int{ColumnString, ColumnString},
			Columns: []any{
				stringColumn(raw, count),
				secondStringColumn(raw, count),
			},
		}, nil
	case C.VEV_COLUMN_BATCH_ENTITY_STRING_INT:
		return &ColumnResult{
			Count: count,
			Kinds: []int{ColumnEntity, ColumnString, ColumnInt},
			Columns: []any{
				entityColumn(C.vev_column_batch_entities_data(raw), count),
				stringColumn(raw, count),
				intColumn(C.vev_column_batch_ints_data(raw), count),
			},
		}, nil
	default:
		return nil, nil
	}
}

func (db *DB) Pull(pattern string, entity uint64) (Value, error) {
	patternText := cstring(pattern)
	defer C.free(unsafe.Pointer(patternText))
	raw := C.vev_pull_edn(db.raw, patternText, C.ulonglong(entity))
	handle, err := newValueHandle(raw)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	return handle.Value(), nil
}

func (db *DB) PullPrepared(pattern *PreparedPullPattern, entity uint64) (Value, error) {
	raw := C.vev_pull_prepared(db.raw, pattern.raw, C.ulonglong(entity))
	handle, err := newValueHandle(raw)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	return handle.Value(), nil
}

func (db *DB) PullEDN(pattern string, entity uint64) (string, error) {
	patternText := cstring(pattern)
	defer C.free(unsafe.Pointer(patternText))
	raw := C.vev_pull_edn(db.raw, patternText, C.ulonglong(entity))
	handle, err := newValueHandle(raw)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	return handle.EDN(), nil
}

func (db *DB) PullLookupRefString(pattern string, attr string, value string) (Value, error) {
	patternText := cstring(pattern)
	attrText := cstring(attr)
	valueText := cstring(value)
	defer C.free(unsafe.Pointer(patternText))
	defer C.free(unsafe.Pointer(attrText))
	defer C.free(unsafe.Pointer(valueText))
	raw := C.vev_pull_lookup_ref_string_edn(db.raw, patternText, attrText, valueText)
	handle, err := newValueHandle(raw)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	return handle.Value(), nil
}

func (db *DB) PullMany(pattern string, entities []uint64) (Value, error) {
	patternText := cstring(pattern)
	defer C.free(unsafe.Pointer(patternText))
	var ptr *C.ulonglong
	if len(entities) > 0 {
		ptr = (*C.ulonglong)(unsafe.Pointer(&entities[0]))
	}
	raw := C.vev_pull_many_edn(db.raw, patternText, ptr, C.int(len(entities)))
	handle, err := newValueHandle(raw)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	return handle.Value(), nil
}

func (db *DB) PullManyPrepared(pattern *PreparedPullPattern, entities []uint64) (Value, error) {
	var ptr *C.ulonglong
	if len(entities) > 0 {
		ptr = (*C.ulonglong)(unsafe.Pointer(&entities[0]))
	}
	raw := C.vev_pull_many_prepared(db.raw, pattern.raw, ptr, C.int(len(entities)))
	handle, err := newValueHandle(raw)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	return handle.Value(), nil
}

func (db *DB) DBWith(tx string) (*DB, error) {
	txText := cstring(tx)
	defer C.free(unsafe.Pointer(txText))
	raw := C.vev_db_with_edn(db.raw, txText)
	if raw == nil {
		return nil, fmt.Errorf("failed to create DB snapshot")
	}
	return &DB{raw: raw}, nil
}

func (db *DB) WithReport(tx string) (*TxReport, error) {
	txText := cstring(tx)
	defer C.free(unsafe.Pointer(txText))
	raw := C.vev_with_edn_report(db.raw, txText)
	if raw == nil {
		return nil, fmt.Errorf("failed to transact against DB snapshot")
	}
	return &TxReport{raw: raw}, nil
}

type PreparedQuery struct {
	raw C.vev_prepared_query_t
}

func Prepare(query string) (*PreparedQuery, error) {
	queryText := cstring(query)
	defer C.free(unsafe.Pointer(queryText))
	raw := C.vev_prepare_query_edn(queryText)
	if raw == nil {
		return nil, fmt.Errorf("failed to prepare query")
	}
	if !bool(C.vev_prepared_query_ok(raw)) {
		err := ownedString(C.vev_prepared_query_error(raw))
		C.vev_prepared_query_free(raw)
		return nil, fmt.Errorf("%s", err)
	}
	return &PreparedQuery{raw: raw}, nil
}

func ParseClauseEDN(clause string) string {
	clauseText := cstring(clause)
	defer C.free(unsafe.Pointer(clauseText))
	return ownedString(C.vev_parse_clause_edn(clauseText))
}

type PreparedPullPattern struct {
	raw C.vev_prepared_pull_pattern_t
}

func PreparePullPattern(pattern string) (*PreparedPullPattern, error) {
	patternText := cstring(pattern)
	defer C.free(unsafe.Pointer(patternText))
	raw := C.vev_prepare_pull_pattern_edn(patternText)
	if raw == nil {
		return nil, fmt.Errorf("failed to prepare pull pattern")
	}
	if !bool(C.vev_prepared_pull_pattern_ok(raw)) {
		err := ownedString(C.vev_prepared_pull_pattern_error(raw))
		C.vev_prepared_pull_pattern_free(raw)
		return nil, fmt.Errorf("%s", err)
	}
	return &PreparedPullPattern{raw: raw}, nil
}

func (p *PreparedPullPattern) Close() {
	if p.raw != nil {
		C.vev_prepared_pull_pattern_free(p.raw)
		p.raw = nil
	}
}

func (p *PreparedPullPattern) EDN() string {
	return ownedString(C.vev_prepared_pull_pattern_edn(p.raw))
}

func (q *PreparedQuery) Close() {
	if q.raw != nil {
		C.vev_prepared_query_free(q.raw)
		q.raw = nil
	}
}

func (q *PreparedQuery) EDN() string {
	return ownedString(C.vev_prepared_query_edn(q.raw))
}

func (q *PreparedQuery) Query(conn *Conn, inputs string) string {
	inputsText := cstring(inputs)
	defer C.free(unsafe.Pointer(inputsText))
	return ownedString(C.vev_query_prepared_with_inputs(conn.raw, q.raw, inputsText))
}

func (q *PreparedQuery) QueryRows(conn *Conn, inputs string) (*ResultSet, error) {
	inputsText := cstring(inputs)
	defer C.free(unsafe.Pointer(inputsText))
	raw := C.vev_query_prepared_result_with_inputs(conn.raw, q.raw, inputsText)
	return newResultSet(raw)
}

func (q *PreparedQuery) Statement() (*Statement, error) {
	raw := C.vev_stmt_create(q.raw)
	if raw == nil {
		return nil, fmt.Errorf("failed to create statement")
	}
	return &Statement{raw: raw}, nil
}

type Statement struct {
	raw C.vev_stmt_t
}

func (s *Statement) Close() {
	if s.raw != nil {
		C.vev_stmt_free(s.raw)
		s.raw = nil
	}
}

func (s *Statement) BindString(value string) error {
	C.vev_stmt_clear(s.raw)
	valueText := cstring(value)
	defer C.free(unsafe.Pointer(valueText))
	if !bool(C.vev_stmt_bind_string(s.raw, valueText)) {
		return fmt.Errorf("failed to bind string")
	}
	return nil
}

func (s *Statement) QueryRows(conn *Conn) (*ResultSet, error) {
	raw := C.vev_query_stmt_result(conn.raw, s.raw)
	return newResultSet(raw)
}

func (s *Statement) QueryColumns(conn *Conn) (*ColumnResult, error) {
	raw := C.vev_query_stmt_column_batch(conn.raw, s.raw)
	return columnResultFromRaw(raw)
}

type Entity uint64
type Keyword string
type Symbol string
type UUID string

const (
	ColumnEntity = 1
	ColumnString = 2
	ColumnInt    = 3
)

type MapEntry struct {
	Key   Value
	Value Value
}

type MapValue []MapEntry
type Value any

type ColumnResult struct {
	Count   int
	Kinds   []int
	Columns []any
}

func entityColumn(ptr *C.ulonglong, count int) []Entity {
	if ptr == nil || count <= 0 {
		return nil
	}
	values := unsafe.Slice(ptr, count)
	out := make([]Entity, count)
	for index, value := range values {
		out[index] = Entity(value)
	}
	return out
}

func intColumn(ptr *C.longlong, count int) []int64 {
	if ptr == nil || count <= 0 {
		return nil
	}
	values := unsafe.Slice(ptr, count)
	out := make([]int64, count)
	for index, value := range values {
		out[index] = int64(value)
	}
	return out
}

func stringColumn(batch C.vev_column_batch_t, count int) []string {
	dictionaryCount := int(C.vev_column_batch_string_dictionary_count(batch))
	dictionaryData := C.vev_column_batch_string_dictionary_data_array(batch)
	dictionaryLengths := C.vev_column_batch_string_dictionary_lengths_data(batch)
	stringIndices := C.vev_column_batch_string_indices_data(batch)
	if dictionaryCount > 0 && dictionaryData != nil && dictionaryLengths != nil && stringIndices != nil {
		data := unsafe.Slice(dictionaryData, dictionaryCount)
		lengths := unsafe.Slice(dictionaryLengths, dictionaryCount)
		indices := unsafe.Slice(stringIndices, count)
		dictionary := make([]string, dictionaryCount)
		for index := range dictionary {
			dictionary[index] = C.GoStringN((*C.char)(data[index]), lengths[index])
		}
		out := make([]string, count)
		for index, dictionaryIndex := range indices {
			out[index] = dictionary[dictionaryIndex]
		}
		return out
	}

	stringData := C.vev_column_batch_string_data_array(batch)
	stringLengths := C.vev_column_batch_string_lengths_data(batch)
	if stringData == nil || stringLengths == nil || count <= 0 {
		return nil
	}
	data := unsafe.Slice(stringData, count)
	lengths := unsafe.Slice(stringLengths, count)
	out := make([]string, count)
	for index := range out {
		out[index] = C.GoStringN((*C.char)(data[index]), lengths[index])
	}
	return out
}

func secondStringColumn(batch C.vev_column_batch_t, count int) []string {
	stringData := C.vev_column_batch_second_string_data_array(batch)
	stringLengths := C.vev_column_batch_second_string_lengths_data(batch)
	if stringData == nil || stringLengths == nil {
		return []string{}
	}
	data := unsafe.Slice(stringData, count)
	lengths := unsafe.Slice(stringLengths, count)
	out := make([]string, count)
	for i := range count {
		out[i] = C.GoStringN((*C.char)(data[i]), C.int(lengths[i]))
	}
	return out
}

func (r *ColumnResult) Rows() [][]Value {
	rows := make([][]Value, 0, r.Count)
	for row := 0; row < r.Count; row++ {
		values := make([]Value, 0, len(r.Columns))
		for _, column := range r.Columns {
			switch valuesColumn := column.(type) {
			case []Entity:
				values = append(values, valuesColumn[row])
			case []string:
				values = append(values, valuesColumn[row])
			case []int64:
				values = append(values, valuesColumn[row])
			}
		}
		rows = append(rows, values)
	}
	return rows
}

func mapGet(value Value, key string) (Value, bool) {
	items, ok := value.(MapValue)
	if !ok {
		return nil, false
	}
	for _, item := range items {
		switch k := item.Key.(type) {
		case Keyword:
			if string(k) == key {
				return item.Value, true
			}
		case string:
			if k == key {
				return item.Value, true
			}
		case Symbol:
			if string(k) == key {
				return item.Value, true
			}
		case UUID:
			if string(k) == key {
				return item.Value, true
			}
		}
	}
	return nil, false
}

func valueFromC(value C.vev_value_t) Value {
	switch C.vev_value_kind(value) {
	case C.VEV_VALUE_NIL:
		return nil
	case C.VEV_VALUE_ENTITY:
		return Entity(C.vev_value_entity(value))
	case C.VEV_VALUE_STRING:
		return ownedString(C.vev_value_text(value))
	case C.VEV_VALUE_INT:
		return int64(C.vev_value_int(value))
	case C.VEV_VALUE_FLOAT:
		return float64(C.vev_value_float(value))
	case C.VEV_VALUE_BOOL:
		return bool(C.vev_value_bool(value))
	case C.VEV_VALUE_KEYWORD:
		return Keyword(ownedString(C.vev_value_text(value)))
	case C.VEV_VALUE_SYMBOL:
		return Symbol(ownedString(C.vev_value_text(value)))
	case C.VEV_VALUE_UUID:
		return UUID(ownedString(C.vev_value_text(value)))
	case C.VEV_VALUE_INSTANT:
		return time.UnixMilli(int64(C.vev_value_int(value))).UTC()
	case C.VEV_VALUE_VECTOR:
		count := int(C.vev_value_item_count(value))
		out := make([]Value, 0, count)
		for i := 0; i < count; i++ {
			out = append(out, valueFromC(C.vev_value_item(value, C.int(i))))
		}
		return out
	case C.VEV_VALUE_MAP:
		count := int(C.vev_value_map_count(value))
		out := make(MapValue, 0, count)
		for i := 0; i < count; i++ {
			out = append(out, MapEntry{
				Key:   valueFromC(C.vev_value_map_key(value, C.int(i))),
				Value: valueFromC(C.vev_value_map_value(value, C.int(i))),
			})
		}
		return out
	default:
		return ownedString(C.vev_value_edn(value))
	}
}

type TxReport struct {
	raw C.vev_tx_report_t
}

func (r *TxReport) Close() {
	if r.raw != nil {
		C.vev_tx_report_free(r.raw)
		r.raw = nil
	}
}

func (r *TxReport) EDN() string {
	return ownedString(C.vev_tx_report_edn(r.raw))
}

func (r *TxReport) Value() Value {
	return valueFromC(C.vev_tx_report_value(r.raw))
}

func (r *TxReport) DBBefore() (*DB, error) {
	raw := C.vev_tx_report_db_before(r.raw)
	if raw == nil {
		return nil, fmt.Errorf("transaction report has no db-before")
	}
	return &DB{raw: raw}, nil
}

func (r *TxReport) DBAfter() (*DB, error) {
	raw := C.vev_tx_report_db_after(r.raw)
	if raw == nil {
		return nil, fmt.Errorf("transaction report has no db-after")
	}
	return &DB{raw: raw}, nil
}

type TxReportArray struct {
	raw C.vev_tx_report_array_t
}

func (a *TxReportArray) Close() {
	if a.raw != nil {
		C.vev_tx_report_array_free(a.raw)
		a.raw = nil
	}
}

func (a *TxReportArray) Values() []Value {
	if a.raw == nil {
		return nil
	}
	count := int(C.vev_tx_report_array_count(a.raw))
	out := make([]Value, 0, count)
	for index := 0; index < count; index++ {
		report := C.vev_tx_report_array_get(a.raw, C.int(index))
		out = append(out, valueFromC(C.vev_tx_report_value(report)))
	}
	return out
}

type EntityView struct {
	raw C.vev_entity_t
}

func (e *EntityView) Close() {
	if e.raw != nil {
		C.vev_entity_free(e.raw)
		e.raw = nil
	}
}

func (e *EntityView) Found() bool {
	return bool(C.vev_entity_found(e.raw))
}

func (e *EntityView) ID() uint64 {
	return uint64(C.vev_entity_id(e.raw))
}

func (e *EntityView) Contains(attr string) bool {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	return bool(C.vev_entity_contains(e.raw, attrText))
}

func (e *EntityView) Get(attr string) (Value, error) {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	handle, err := newValueHandle(C.vev_entity_get(e.raw, attrText))
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	return handle.Value(), nil
}

func (e *EntityView) Values(attr string) ([]Value, error) {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	handle, err := newValueHandle(C.vev_entity_values(e.raw, attrText))
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	values, ok := handle.Value().([]Value)
	if !ok {
		return nil, fmt.Errorf("expected entity values vector")
	}
	return values, nil
}

func (e *EntityView) Ref(attr string) (*EntityView, error) {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	raw := C.vev_entity_ref(e.raw, attrText)
	if raw == nil {
		return nil, fmt.Errorf("failed to create referenced entity view")
	}
	return &EntityView{raw: raw}, nil
}

func (e *EntityView) Refs(attr string) []Entity {
	attrText := cstring(attr)
	defer C.free(unsafe.Pointer(attrText))
	raw := C.vev_entity_refs(e.raw, attrText)
	if raw == nil {
		return nil
	}
	defer C.vev_u64_array_free(raw)
	count := int(C.vev_u64_array_count(raw))
	out := make([]Entity, 0, count)
	for index := 0; index < count; index++ {
		out = append(out, Entity(C.vev_u64_array_value(raw, C.int(index))))
	}
	return out
}

func (e *EntityView) Touch() (Value, error) {
	handle, err := newValueHandle(C.vev_entity_touch(e.raw))
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	return handle.Value(), nil
}

type ValueHandle struct {
	raw C.vev_value_handle_t
}

func newValueHandle(raw C.vev_value_handle_t) (*ValueHandle, error) {
	if raw == nil {
		return nil, fmt.Errorf("pull returned null value handle")
	}
	return &ValueHandle{raw: raw}, nil
}

func (h *ValueHandle) Close() {
	if h.raw != nil {
		C.vev_value_handle_free(h.raw)
		h.raw = nil
	}
}

func (h *ValueHandle) Value() Value {
	return valueFromC(C.vev_value_handle_value(h.raw))
}

func (h *ValueHandle) EDN() string {
	return ownedString(C.vev_value_handle_edn(h.raw))
}

type ResultSet struct {
	raw C.vev_result_t
}

func newResultSet(raw C.vev_result_t) (*ResultSet, error) {
	if raw == nil {
		return nil, fmt.Errorf("query returned null result")
	}
	if !bool(C.vev_result_ok(raw)) {
		err := ownedString(C.vev_result_error(raw))
		C.vev_result_free(raw)
		return nil, fmt.Errorf("%s", err)
	}
	return &ResultSet{raw: raw}, nil
}

func (r *ResultSet) Close() {
	if r.raw != nil {
		C.vev_result_free(r.raw)
		r.raw = nil
	}
}

func (r *ResultSet) RowCount() int {
	return int(C.vev_result_row_count(r.raw))
}

func (r *ResultSet) Rows() [][]Value {
	rows := make([][]Value, 0, r.RowCount())
	for row := 0; row < r.RowCount(); row++ {
		values := make([]Value, 0)
		for col := 0; col < int(C.vev_result_value_count(r.raw, C.int(row))); col++ {
			values = append(values, valueFromC(C.vev_result_value(r.raw, C.int(row), C.int(col))))
		}
		for pull := 0; pull < int(C.vev_result_pull_count(r.raw, C.int(row))); pull++ {
			values = append(values, valueFromC(C.vev_result_pull(r.raw, C.int(row), C.int(pull))))
		}
		rows = append(rows, values)
	}
	return rows
}

func (r *ResultSet) Scalar() (Value, error) {
	rows := r.Rows()
	if len(rows) == 1 && len(rows[0]) == 1 {
		return rows[0][0], nil
	}
	return nil, fmt.Errorf("expected one scalar result, got %#v", rows)
}

func mustContain(label string, text string, needles ...string) {
	for _, needle := range needles {
		if !strings.Contains(text, needle) {
			panic(fmt.Sprintf("%s missing %q in %s", label, needle, text))
		}
	}
}

func removeSqliteFiles(path string) {
	_ = os.Remove(path)
	_ = os.Remove(path + "-wal")
	_ = os.Remove(path + "-shm")
}

func mustEqual(label string, got any, want any) {
	if !reflect.DeepEqual(got, want) {
		panic(fmt.Sprintf("%s got %#v, want %#v", label, got, want))
	}
}

func Smoke() {
	conn, err := CreateConn()
	if err != nil {
		panic(err)
	}
	defer conn.Close()

	tx := conn.Transact(`
		[{:db/id 1 :user/name "Ada" :user/email "ada@example.com"}
		 {:db/id 2 :user/name "Grace" :user/email "grace@example.com"}]
	`)
	fmt.Println("tx:", tx)
	mustContain("tx", tx, ":ok true")

	result := conn.QueryText(`
		[:find ?name
		 :in $ [?email ...]
		 :where [?e :user/email ?email]
		        [?e :user/name ?name]]
	`, `[["ada@example.com" "grace@example.com"]]`)
	fmt.Println("input-collection:", result)
	mustContain("collection query", result, `"Ada"`, `"Grace"`)

	oneShotRows, err := conn.Q(`[:find ?name :where [?e :user/name ?name]]`, "[]")
	if err != nil {
		panic(err)
	}
	oneShotNames := []string{}
	for _, row := range oneShotRows.Rows() {
		oneShotNames = append(oneShotNames, row[0].(string))
	}
	sort.Strings(oneShotNames)
	mustEqual("one-shot query rows", oneShotNames, []string{"Ada", "Grace"})
	oneShotRows.Close()

	query, err := Prepare(`
		[:find ?e ?email
		 :in $ ?needle
		 :where [?e :user/email ?email]
		        [(= ?email ?needle)]]
	`)
	if err != nil {
		panic(err)
	}
	defer query.Close()

	preparedAST := query.EDN()
	if !strings.Contains(preparedAST, ":clauses") || !strings.Contains(preparedAST, ":input-specs") {
		panic("prepared query AST did not expose parser keys")
	}
	clauseAST := ParseClauseEDN("[?e :user/email ?email]")
	if !strings.Contains(clauseAST, ":clauses") || !strings.Contains(clauseAST, ":user/email") {
		panic("parse-clause AST did not expose parser keys")
	}

	prepared := query.Query(conn, `["grace@example.com"]`)
	fmt.Println("prepared:", prepared)
	mustContain("prepared query", prepared, "2", `"grace@example.com"`)

	rows, err := query.QueryRows(conn, `["grace@example.com"]`)
	if err != nil {
		panic(err)
	}
	typedRows := rows.Rows()
	rows.Close()
	fmt.Println("typed rows:", typedRows)
	mustEqual("typed rows", typedRows, [][]Value{{Entity(2), "grace@example.com"}})

	stmt, err := query.Statement()
	if err != nil {
		panic(err)
	}
	defer stmt.Close()
	if err := stmt.BindString("grace@example.com"); err != nil {
		panic(err)
	}
	stmtRows, err := stmt.QueryRows(conn)
	if err != nil {
		panic(err)
	}
	statementRows := stmtRows.Rows()
	stmtRows.Close()
	mustEqual("statement rows", statementRows, [][]Value{{Entity(2), "grace@example.com"}})

	conn.Transact(`
		[[:db/add 90 :db/ident :user/email]
		 [:db/add 90 :db/unique :db.unique/identity]]
	`)

	conn.Transact(`
		[[:db/add 100 :db/ident :user/friend]
		 [:db/add 100 :db/valueType :db.type/ref]
		 [:db/add 1 :user/friend 2]]
	`)

	pullQuery, err := Prepare(`[:find (pull ?e [:user/name {:user/friend [:user/name]}]) :where [?e :user/name "Ada"]]`)
	if err != nil {
		panic(err)
	}
	defer pullQuery.Close()
	pullRows, err := pullQuery.QueryRows(conn, "[]")
	if err != nil {
		panic(err)
	}
	pulled, err := pullRows.Scalar()
	pullRows.Close()
	if err != nil {
		panic(err)
	}
	fmt.Println("pull:", pulled)
	friend, _ := mapGet(pulled, ":user/friend")
	friendName, _ := mapGet(friend, ":user/name")
	name, _ := mapGet(pulled, ":user/name")
	mustEqual("pull name", name, "Ada")
	mustEqual("pull friend", friendName, "Grace")

	snapshot, err := conn.DB()
	if err != nil {
		panic(err)
	}
	defer snapshot.Close()

	directPull, err := snapshot.Pull("[:user/name {:user/friend [:user/name]}]", 1)
	if err != nil {
		panic(err)
	}
	fmt.Println("direct pull:", directPull)
	lookupPull, err := snapshot.PullLookupRefString("[:user/name]", ":user/email", "ada@example.com")
	if err != nil {
		panic(err)
	}
	lookupName, _ := mapGet(lookupPull, ":user/name")
	mustEqual("lookup pull", lookupName, "Ada")
	manyPull, err := snapshot.PullMany("[:user/name]", []uint64{1, 2})
	if err != nil {
		panic(err)
	}
	manyNames := make([]string, 0)
	for _, item := range manyPull.([]Value) {
		if name, ok := mapGet(item, ":user/name"); ok {
			manyNames = append(manyNames, name.(string))
		}
	}
	sort.Strings(manyNames)
	mustEqual("pull many", manyNames, []string{"Ada", "Grace"})

	adaEntity, err := snapshot.Entity(1)
	if err != nil {
		panic(err)
	}
	defer adaEntity.Close()
	friendEntity, err := adaEntity.Ref(":user/friend")
	if err != nil {
		panic(err)
	}
	defer friendEntity.Close()
	lookupEntity, err := snapshot.EntityLookupRefString(":user/email", "ada@example.com")
	if err != nil {
		panic(err)
	}
	defer lookupEntity.Close()
	identEntity, err := snapshot.EntityIdent(":user/email")
	if err != nil {
		panic(err)
	}
	defer identEntity.Close()
	entityName, err := adaEntity.Get(":user/name")
	if err != nil {
		panic(err)
	}
	entityNames, err := adaEntity.Values(":user/name")
	if err != nil {
		panic(err)
	}
	friendNameValue, err := friendEntity.Get(":user/name")
	if err != nil {
		panic(err)
	}
	lookupNameValue, err := lookupEntity.Get(":user/name")
	if err != nil {
		panic(err)
	}
	touchedEntity, err := adaEntity.Touch()
	if err != nil {
		panic(err)
	}
	touchedName, _ := mapGet(touchedEntity, ":user/name")
	fmt.Println("entity view:", touchedEntity)
	mustEqual("entity found", adaEntity.Found(), true)
	mustEqual("entity id", adaEntity.ID(), uint64(1))
	mustEqual("entity contains", adaEntity.Contains(":user/name"), true)
	mustEqual("entity get", entityName, "Ada")
	mustEqual("entity values", entityNames, []Value{"Ada"})
	mustEqual("entity ref", friendEntity.ID(), uint64(2))
	mustEqual("entity ref name", friendNameValue, "Grace")
	mustEqual("entity refs", adaEntity.Refs(":user/friend"), []Entity{Entity(2)})
	mustEqual("entity lookup", lookupEntity.ID(), uint64(1))
	mustEqual("entity lookup name", lookupNameValue, "Ada")
	mustEqual("entity ident", identEntity.ID(), uint64(90))
	mustEqual("entity touch", touchedName, "Ada")

	preparedPattern, err := PreparePullPattern("[:user/name]")
	if err != nil {
		panic(err)
	}
	defer preparedPattern.Close()
	preparedPatternAST := preparedPattern.EDN()
	if !strings.Contains(preparedPatternAST, ":pattern") || !strings.Contains(preparedPatternAST, ":attr") {
		panic("prepared pull pattern AST did not expose parser keys")
	}
	preparedPull, err := snapshot.PullPrepared(preparedPattern, 1)
	if err != nil {
		panic(err)
	}
	fmt.Println("prepared direct pull:", preparedPull)
	preparedName, _ := mapGet(preparedPull, ":user/name")
	mustEqual("prepared pull", preparedName, "Ada")
	preparedMany, err := snapshot.PullManyPrepared(preparedPattern, []uint64{1, 2})
	if err != nil {
		panic(err)
	}
	preparedNames := make([]string, 0)
	for _, item := range preparedMany.([]Value) {
		if name, ok := mapGet(item, ":user/name"); ok {
			preparedNames = append(preparedNames, name.(string))
		}
	}
	sort.Strings(preparedNames)
	mustEqual("prepared pull many", preparedNames, []string{"Ada", "Grace"})

	allEmailTexts, err := Prepare(`[:find ?email :where [?e :user/email ?email]]`)
	if err != nil {
		panic(err)
	}
	defer allEmailTexts.Close()
	columns, err := snapshot.QueryColumns(allEmailTexts, "[]")
	if err != nil {
		panic(err)
	}
	if columns == nil {
		panic("expected string column batch")
	}
	columnRows := columns.Rows()
	sort.Slice(columnRows, func(i, j int) bool {
		return fmt.Sprintf("%#v", columnRows[i]) < fmt.Sprintf("%#v", columnRows[j])
	})
	fmt.Println("column batch rows:", columnRows)
	mustEqual("column batch kinds", columns.Kinds, []int{ColumnString})
	mustEqual("column batch rows", columnRows, [][]Value{{"ada@example.com"}, {"grace@example.com"}})

	allEmailStmt, err := allEmailTexts.Statement()
	if err != nil {
		panic(err)
	}
	defer allEmailStmt.Close()
	liveColumns, err := allEmailStmt.QueryColumns(conn)
	if err != nil {
		panic(err)
	}
	if liveColumns == nil {
		panic("expected live statement column batch")
	}
	liveColumnRows := liveColumns.Rows()
	sort.Slice(liveColumnRows, func(i, j int) bool {
		return fmt.Sprintf("%#v", liveColumnRows[i]) < fmt.Sprintf("%#v", liveColumnRows[j])
	})
	mustEqual("live statement column batch kinds", liveColumns.Kinds, []int{ColumnString})
	mustEqual("live statement column batch rows", liveColumnRows, columnRows)
	snapshotColumns, err := snapshot.QueryStatementColumns(allEmailStmt)
	if err != nil {
		panic(err)
	}
	if snapshotColumns == nil {
		panic("expected snapshot statement column batch")
	}
	snapshotColumnRows := snapshotColumns.Rows()
	sort.Slice(snapshotColumnRows, func(i, j int) bool {
		return fmt.Sprintf("%#v", snapshotColumnRows[i]) < fmt.Sprintf("%#v", snapshotColumnRows[j])
	})
	mustEqual("snapshot statement column batch kinds", snapshotColumns.Kinds, []int{ColumnString})
	mustEqual("snapshot statement column batch rows", snapshotColumnRows, columnRows)

	conn.Transact(`[{:db/id 3 :user/name "Alan" :user/email "alan@example.com"}]`)
	current := query.Query(conn, `["alan@example.com"]`)
	old := snapshot.QueryPrepared(query, `["alan@example.com"]`)
	fmt.Println("current-db:", current)
	fmt.Println("snapshot-db:", old)
	mustContain("current DB query", current, "3", `"alan@example.com"`)
	if strings.Contains(old, "alan@example.com") {
		panic("snapshot unexpectedly observed later transaction")
	}

	currentRows, err := query.QueryRows(conn, `["alan@example.com"]`)
	if err != nil {
		panic(err)
	}
	oldRows, err := snapshot.QueryRows(query, `["alan@example.com"]`)
	if err != nil {
		panic(err)
	}
	if currentRows.RowCount() != 1 || oldRows.RowCount() != 0 {
		panic("unexpected typed snapshot row counts")
	}
	currentRows.Close()
	oldRows.Close()

	withReport, err := snapshot.WithReport(`[{:db/id 4 :user/name "Barbara" :user/email "barbara@example.com"}]`)
	if err != nil {
		panic(err)
	}
	reportBefore, err := withReport.DBBefore()
	if err != nil {
		panic(err)
	}
	reportAfter, err := withReport.DBAfter()
	if err != nil {
		panic(err)
	}
	reportBeforeRows, err := reportBefore.QueryRows(query, `["barbara@example.com"]`)
	if err != nil {
		panic(err)
	}
	reportAfterRows, err := reportAfter.QueryRows(query, `["barbara@example.com"]`)
	if err != nil {
		panic(err)
	}
	if reportBeforeRows.RowCount() != 0 || reportAfterRows.RowCount() != 1 {
		panic("unexpected with report DB rows")
	}
	reportBeforeRows.Close()
	reportAfterRows.Close()
	reportBefore.Close()
	reportAfter.Close()
	withReport.Close()

	nextDB, err := snapshot.DBWith(`[{:db/id 4 :user/name "Barbara" :user/email "barbara@example.com"}]`)
	if err != nil {
		panic(err)
	}
	defer nextDB.Close()
	derived, err := ConnFromDB(nextDB)
	if err != nil {
		panic(err)
	}
	defer derived.Close()
	barbara := query.Query(derived, `["barbara@example.com"]`)
	mustContain("conn-from-db", barbara, "4", `"barbara@example.com"`)

	sqlitePath := "tmp.vev.go.sqlite"
	removeSqliteFiles(sqlitePath)
	defer removeSqliteFiles(sqlitePath)
	durable, err := Connect(sqlitePath)
	if err != nil {
		panic(err)
	}
	if durable.Backend() != "sqlite" || durable.Path() != sqlitePath || durable.BasisT() != 0 || durable.TxCount() != 0 {
		panic(fmt.Sprintf("unexpected durable metadata: backend=%s path=%s basis=%d tx-count=%d info=%s", durable.Backend(), durable.Path(), durable.BasisT(), durable.TxCount(), durable.InfoEDN()))
	}
	report, err := durable.Transact(`[{:db/id 1 :user/name "Durable Ada" :user/email "durable-ada@example.com"}]`)
	if err != nil {
		panic(err)
	}
	report.Close()
	firstBasis := durable.BasisT()
	if firstBasis == 0 || durable.TxCount() != 1 {
		panic("unexpected durable metadata after transact")
	}
	bulkA, err := NewTxBuilder(3)
	if err != nil {
		panic(err)
	}
	defer bulkA.Close()
	bulkB, err := NewTxBuilder(1)
	if err != nil {
		panic(err)
	}
	defer bulkB.Close()
	if err := bulkA.AddString(2, ":user/name", "Durable Grace"); err != nil {
		panic(err)
	}
	if err := bulkA.AddInt(2, ":user/age", 37); err != nil {
		panic(err)
	}
	if err := bulkA.AddBool(2, ":user/active", true); err != nil {
		panic(err)
	}
	if err := bulkB.AddString(3, ":user/name", "Durable Hedy"); err != nil {
		panic(err)
	}
	bulkReport, err := durable.TransactBulk([]*TxBuilder{bulkA, bulkB})
	if err != nil {
		panic(err)
	}
	bulkValue := bulkReport.Value()
	bulkReport.Close()
	bulkOK, _ := mapGet(bulkValue, ":ok")
	mustEqual("durable bulk ok", bulkOK, true)
	if durable.BasisT() != firstBasis+1 || durable.TxCount() != 2 {
		panic("unexpected durable metadata after bulk transact")
	}
	logicalA, err := NewTxBuilder(2)
	if err != nil {
		panic(err)
	}
	defer logicalA.Close()
	logicalB, err := NewTxBuilder(2)
	if err != nil {
		panic(err)
	}
	defer logicalB.Close()
	if err := logicalA.AddString(4, ":user/name", "Durable Ada"); err != nil {
		panic(err)
	}
	if err := logicalA.AddKeyword(4, ":user/role", ":role/admin"); err != nil {
		panic(err)
	}
	if err := logicalB.AddString(5, ":user/name", "Durable Dorothy"); err != nil {
		panic(err)
	}
	if err := logicalB.AddSymbol(5, ":user/source", "source/import"); err != nil {
		panic(err)
	}
	logicalReports, err := durable.TransactLogicalBulk([]*TxBuilder{logicalA, logicalB})
	if err != nil {
		panic(err)
	}
	logicalValues := logicalReports.Values()
	logicalReports.Close()
	if len(logicalValues) != 2 {
		panic("unexpected logical group report count")
	}
	for _, value := range logicalValues {
		ok, _ := mapGet(value, ":ok")
		mustEqual("logical group ok", ok, true)
	}
	emptyLogicalReports, err := durable.TransactLogicalBulk(nil)
	if err != nil {
		panic(err)
	}
	mustEqual("empty logical group", len(emptyLogicalReports.Values()), 0)
	emptyLogicalReports.Close()
	ednReports, err := durable.TransactLogical([]string{
		`[{:db/id 6 :user/name "Durable Katherine"}]`,
		`[{:db/id 7 :user/name "Durable Mary"}]`,
	})
	if err != nil {
		panic(err)
	}
	ednValues := ednReports.Values()
	ednReports.Close()
	if len(ednValues) != 2 {
		panic("unexpected EDN logical group report count")
	}
	for _, value := range ednValues {
		ok, _ := mapGet(value, ":ok")
		mustEqual("EDN logical group ok", ok, true)
	}
	if durable.BasisT() != firstBasis+5 || durable.TxCount() != 6 {
		panic("unexpected durable metadata after logical transact")
	}
	durableDB, err := durable.DB()
	if err != nil {
		panic(err)
	}
	durable.Close()
	reopened, err := Connect(sqlitePath)
	if err != nil {
		panic(err)
	}
	defer reopened.Close()
	if reopened.BasisT() != firstBasis+5 || reopened.TxCount() != 6 {
		panic("unexpected reopened durable metadata")
	}
	reopenedDB, err := reopened.DB()
	if err != nil {
		panic(err)
	}
	defer reopenedDB.Close()
	durableRows, err := reopenedDB.QueryRows(query, `["durable-ada@example.com"]`)
	if err != nil {
		panic(err)
	}
	if durableRows.RowCount() != 1 {
		panic("unexpected reopened durable rows")
	}
	durableRows.Close()
	durableEntity, err := reopenedDB.Entity(1)
	if err != nil {
		panic(err)
	}
	defer durableEntity.Close()
	durableEntityName, err := durableEntity.Get(":user/name")
	if err != nil {
		panic(err)
	}
	durableEntityEmail, err := durableEntity.Get(":user/email")
	if err != nil {
		panic(err)
	}
	mustEqual("durable entity name", durableEntityName, "Durable Ada")
	mustEqual("durable entity email", durableEntityEmail, "durable-ada@example.com")
	durableDB.Close()

}
