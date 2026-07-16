;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns export-mbrainz-subset
  (:require [clojure.java.io :as io]
            [datomic.api :as d]))

(def default-uri "datomic:dev://localhost:4334/mbrainz-1968-1973")
(def default-out "build/musicbrainz/vev-mbrainz-subset.edn")
(def default-limit 0)

(def value-attrs
  #{:artist/country
    :artist/endDay
    :artist/endMonth
    :artist/endYear
    :artist/gender
    :artist/gid
    :artist/name
    :artist/sortName
    :artist/startDay
    :artist/startMonth
    :artist/startYear
    :artist/type
    :country/name
    :medium/format
    :medium/name
    :medium/position
    :medium/trackCount
    :medium/tracks
    :release/abstractRelease
    :release/artistCredit
    :release/artists
    :release/barcode
    :release/country
    :release/day
    :release/gid
    :release/language
    :release/media
    :release/month
    :release/name
    :release/packaging
    :release/script
    :release/status
    :release/year
    :track/artistCredit
    :track/artists
    :track/duration
    :track/name
    :track/position})

(def schema-props
  [:db/ident
   :db/valueType
   :db/cardinality
   :db/unique
   :db/isComponent
   :db/index])

(def remap-start 1000000)

(defn make-remapper []
  (atom {:next remap-start
         :ids {}}))

(defn remap-eid! [state eid]
  (let [existing (get-in @state [:ids eid])]
    (if existing
      existing
      (let [mapped (:next @state)]
        (swap! state
               (fn [m]
                 (-> m
                     (assoc :next (inc (:next m)))
                     (assoc-in [:ids eid] mapped))))
        mapped))))

(defn preserve-eid! [state eid]
  (swap! state assoc-in [:ids eid] eid)
  eid)

(defn schema-attr-idents [db]
  (set
    (concat
      value-attrs
      (d/q '[:find [?ident ...]
             :where
             [?attr :db/ident ?ident]
             [?attr :db/unique _]]
           db))))

(defn prepare-schema-identities! [db remap]
  (doseq [ident (concat (schema-attr-idents db) schema-props)
          :let [eid (d/entid db ident)]
          :when eid]
    (preserve-eid! remap eid))
  remap)

(defn tx-value-text [x]
  (cond
    (keyword? x) (str x)
    (uuid? x) (str "#uuid " (pr-str (str x)))
    (string? x) (pr-str x)
    (integer? x) (str x)
    (boolean? x) (str x)
    :else (throw (ex-info "unsupported export value" {:value x :type (type x)}))))

(defn tx-add-text [remap e a v]
  (str "[:db/add " (remap-eid! remap e) " " a " " (tx-value-text v) "]"))

(defn entity-ident [db e]
  (:db/ident (d/entity db e)))

(defn schema-tx [db remap]
  (for [attr (schema-attr-idents db)
        :let [e (d/entid db attr)]
        :when e
        prop schema-props
        :let [v (get (d/entity db e) prop)]
        :when (some? v)]
    (tx-add-text remap e prop (if (keyword? v) v (or (entity-ident db v) v)))))

(defn built-in-schema-ident-tx [db remap]
  (for [ident schema-props
        :let [e (d/entid db ident)]
        :when e]
    (tx-add-text remap e :db/ident ident)))

(defn ref-attr-ids [db]
  (set
    (d/q '[:find [?a ...]
           :in $ [?attr ...]
           :where
           [?a :db/ident ?attr]
           [?a :db/valueType ?vt]
           [?vt :db/ident :db.type/ref]]
         db value-attrs)))

(defn referenced-ident-entity-ids [db]
  (let [ref-attrs (ref-attr-ids db)]
    (set
      (map :v
           (filter
             (fn [datom]
               (contains? ref-attrs (:a datom)))
             (d/datoms db :eavt))))))

(defn ident-tx [db remap]
  (for [e (referenced-ident-entity-ids db)
        :let [ident (entity-ident db e)]
        :when ident
        :let [_ (preserve-eid! remap e)]]
    (tx-add-text remap e :db/ident ident)))

(defn value-tx [db remap]
  (let [attrs (keep #(d/entid db %) value-attrs)
        attr-set (set attrs)
        ref-attrs (ref-attr-ids db)]
    (for [datom (d/datoms db :aevt)
          :when (contains? attr-set (:a datom))
          :let [attr (entity-ident db (:a datom))
                value (if (contains? ref-attrs (:a datom))
                        (remap-eid! remap (:v datom))
                        (:v datom))]]
      (tx-add-text remap (:e datom) attr value))))

(defn write-items! [out-path items]
  (io/make-parents out-path)
  (let [written (atom 0)]
    (with-open [w (io/writer out-path)]
      (.write w "[")
      (doseq [item items]
        (when (pos? @written)
          (.write w "\n "))
        (.write w item)
        (swap! written inc))
      (.write w "]\n"))
    {:path out-path
     :items @written}))

(defn limited [items limit]
  (if (pos? limit)
    (take limit items)
    items))

(defn write-export! [db out-path limit]
  (let [remap (make-remapper)
        _ (prepare-schema-identities! db remap)
        items (limited (concat (built-in-schema-ident-tx db remap)
                               (schema-tx db remap)
                               (ident-tx db remap)
                               (value-tx db remap)) limit)]
    (write-items! out-path items)))

(defn write-split-export! [db out-prefix value-limit]
  (let [remap (make-remapper)
        _ (prepare-schema-identities! db remap)
        schema-path (str out-prefix "-schema.edn")
        values-path (str out-prefix "-values.edn")
        schema-result (write-items! schema-path (concat (built-in-schema-ident-tx db remap)
                                                        (schema-tx db remap)
                                                        (ident-tx db remap)))
        values-result (write-items! values-path (limited (value-tx db remap) value-limit))]
    {:path out-prefix
     :schema-path schema-path
     :schema-items (:items schema-result)
     :values-path values-path
     :values-items (:items values-result)
     :items (+ (:items schema-result) (:items values-result))}))

(defn write-chunked-items! [out-prefix items chunk-size]
  (loop [remaining items
         chunk-index 0
         total 0]
    (let [chunk (doall (take chunk-size remaining))]
      (if (empty? chunk)
        {:chunks chunk-index
         :items total}
        (let [path (format "%s-values-%04d.edn" out-prefix chunk-index)
              result (write-items! path chunk)]
          (recur (drop chunk-size remaining)
                 (inc chunk-index)
                 (+ total (:items result))))))))

(defn write-split-chunked-export! [db out-prefix value-limit chunk-size]
  (let [remap (make-remapper)
        _ (prepare-schema-identities! db remap)
        schema-path (str out-prefix "-schema.edn")
        schema-result (write-items! schema-path (concat (built-in-schema-ident-tx db remap)
                                                        (schema-tx db remap)
                                                        (ident-tx db remap)))
        values-result (write-chunked-items! out-prefix (limited (value-tx db remap) value-limit) chunk-size)]
    {:path out-prefix
     :schema-path schema-path
     :schema-items (:items schema-result)
     :values-prefix out-prefix
     :value-chunks (:chunks values-result)
     :values-items (:items values-result)
     :items (+ (:items schema-result) (:items values-result))}))

(defn -main [& args]
  (let [uri (or (first args) default-uri)
        out-path (or (second args) default-out)
        limit (if-let [limit-text (nth args 2 nil)]
                (parse-long limit-text)
                default-limit)
        mode (or (nth args 3 nil) "single")
        chunk-size (if-let [chunk-text (nth args 4 nil)]
                     (parse-long chunk-text)
                     100000)
        conn (d/connect uri)
        db (d/db conn)
        result (cond
                 (= mode "split") (write-split-export! db out-path limit)
                 (= mode "split-chunks") (write-split-chunked-export! db out-path limit chunk-size)
                 :else (write-export! db out-path limit))]
    (if (= mode "split-chunks")
      (println (str "exported prefix=" (:path result)
                    " schema_path=" (:schema-path result)
                    " schema_items=" (:schema-items result)
                    " values_prefix=" (:values-prefix result)
                    " value_chunks=" (:value-chunks result)
                    " values_items=" (:values-items result)
                    " items=" (:items result)
                    " basis_t=" (d/basis-t db)))
      (if (= mode "split")
      (println (str "exported prefix=" (:path result)
                    " schema_path=" (:schema-path result)
                    " schema_items=" (:schema-items result)
                    " values_path=" (:values-path result)
                    " values_items=" (:values-items result)
                    " items=" (:items result)
                    " basis_t=" (d/basis-t db)))
      (println (str "exported path=" (:path result)
                    " items=" (:items result)
                    " basis_t=" (d/basis-t db)))))
    (shutdown-agents)
    (System/exit 0)))

(apply -main *command-line-args*)
