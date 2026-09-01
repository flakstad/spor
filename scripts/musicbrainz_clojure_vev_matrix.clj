(ns musicbrainz-clojure-vev-matrix
  (:require [clojure.edn :as edn]
            [clojure.string :as str]
            [vev.core :as vev]))

(def default-lib "")
(def default-schema "build/musicbrainz/vev-mbrainz-subset-500-schema.edn")
(def default-values "build/musicbrainz/vev-mbrainz-subset-500-values.edn")
(def default-values-prefix "build/musicbrainz/vev-mbrainz-subset-full-chunked")

(def musicbrainz-rules
  '[[(track-release ?t ?r)
     [?m :medium/tracks ?t]
     [?r :release/media ?m]]
    [(track-info ?t ?track-name ?artist-name ?album ?year)
     [?t :track/name ?track-name]
     [?t :track/artists ?a]
     [?a :artist/name ?artist-name]
     (track-release ?t ?r)
     [?r :release/name ?album]
     [?r :release/year ?year]]
    [(short-track ?a ?t ?len ?max)
     [?t :track/artists ?a]
     [?t :track/duration ?len]
     [(< ?len ?max)]]])

(def workloads
  [{:name "musicbrainz-smoke-country-names"
    :kind :query
    :query '[:find ?country-name
             :where
             [?country :country/name ?country-name]]
    :args []}
   {:name "musicbrainz-real-release-first"
    :kind :query
    :query '[:find ?title ?album ?year
             :in $ ?artist-name
             :where
             [?a :artist/name ?artist-name]
             [?r :release/artists ?a]
             [?r :release/year ?year]
             [(< ?year 1970)]
             [?r :release/name ?album]
             [?r :release/media ?m]
             [?m :medium/tracks ?t]
             [?t :track/name ?title]]
    :args ["The Beatles"]}
   {:name "musicbrainz-real-track-first"
    :kind :query
    :query '[:find ?title ?album ?year
             :in $ ?artist-name
             :where
             [?a :artist/name ?artist-name]
             [?t :track/artists ?a]
             [?t :track/name ?title]
             [?r :release/artists ?a]
             [?r :release/year ?year]
             [(< ?year 1970)]
             [?r :release/name ?album]
             [?r :release/media ?m]
             [?m :medium/tracks ?t]]
    :args ["The Beatles"]}
   {:name "musicbrainz-real-john-lennon-pre-1970-tracks"
    :kind :query
    :query '[:find ?title ?album ?year
             :in $ ?artist-name
             :where
             [?a :artist/name ?artist-name]
             [?r :release/artists ?a]
             [?r :release/year ?year]
             [?r :release/name ?album]
             [(< ?year 1970)]
             [?r :release/media ?m]
             [?m :medium/tracks ?t]
             [?t :track/name ?title]]
    :args ["John Lennon"]}
   {:name "musicbrainz-real-beatles-releases"
    :kind :query
    :query '[:find ?release-name
             :where
             [?artist :artist/name "The Beatles"]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-beatles-short-track-collection"
    :kind :query
    :query '[:find [?track-name ...]
             :where
             [?artist :artist/name "The Beatles"]
             [?track :track/artists ?artist]
             [?track :track/name ?track-name]
             [?track :track/duration ?duration]
             [(< ?duration 300000)]]
    :args []}
   {:name "musicbrainz-real-abbey-road-release-date-tuple"
    :kind :query
    :query '[:find [?year ?month ?day]
             :where
             [?release :release/gid #uuid "eca8996a-a637-3259-ba07-d2573c601a1b"]
             [?release :release/year ?year]
             [?release :release/month ?month]
             [?release :release/day ?day]]
    :args []}
   {:name "musicbrainz-real-beatles-start-year-scalar"
    :kind :query
    :query '[:find ?year .
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/startYear ?year]]
    :args []}
   {:name "musicbrainz-real-abbey-road-track-minutes"
    :kind :query
    :query '[:find ?track-name ?minutes
             :where
             [?release :release/gid #uuid "eca8996a-a637-3259-ba07-d2573c601a1b"]
             [?release :release/media ?medium]
             [?medium :medium/tracks ?track]
             [?track :track/name ?track-name]
             [?track :track/duration ?millis]
             [(quot ?millis 60000) ?minutes]]
    :args []}
   {:name "musicbrainz-real-miles-enum-id"
    :kind :query
    :query '[:find ?id ?type ?gender
             :where
             [?artist :artist/name "Miles Davis"]
             [?artist :artist/gid ?id]
             [?artist :artist/type ?type-entity]
             [?type-entity :db/ident ?type]
             [?artist :artist/gender ?gender-entity]
             [?gender-entity :db/ident ?gender]]
    :args []}
   {:name "musicbrainz-real-beatles-track-count"
    :kind :query
    :query '[:find (count ?track)
             :where
             [?artist :artist/name "The Beatles"]
             [?track :track/artists ?artist]
             [?track :track/name]]
    :args []}
   {:name "musicbrainz-real-beatles-min-max-duration"
    :kind :query
    :query '[:find (min ?dur) (max ?dur)
             :where
             [?artist :artist/name "The Beatles"]
             [?track :track/artists ?artist]
             [?track :track/duration ?dur]]
    :args []}
   {:name "musicbrainz-real-beatles-duration-stats"
    :kind :query
    :query '[:find ?year (median ?millis) (avg ?millis)
             :with ?track
             :where
             [?artist :artist/name "The Beatles"]
             [?release :release/artists ?artist]
             [?release :release/year ?year]
             [?release :release/media ?medium]
             [?medium :medium/tracks ?track]
             [?track :track/duration ?millis]]
    :args []}
   {:name "musicbrainz-real-beatles-duration-stddev"
    :kind :query
    :float-places 6
    :query '[:find ?year (stddev ?millis)
             :with ?track
             :where
             [?artist :artist/name "The Beatles"]
             [?release :release/artists ?artist]
             [?release :release/year ?year]
             [?release :release/media ?medium]
             [?medium :medium/tracks ?track]
             [?track :track/duration ?millis]]
    :args []}
   {:name "musicbrainz-real-beatles-duration-sum"
    :kind :query
    :query '[:find ?year (sum ?millis)
             :with ?track
             :where
             [?artist :artist/name "The Beatles"]
             [?release :release/artists ?artist]
             [?release :release/year ?year]
             [?release :release/media ?medium]
             [?medium :medium/tracks ?track]
             [?track :track/duration ?millis]]
    :args []}
   {:name "musicbrainz-real-lookup-country"
    :kind :query
    :query '[:find ?name
             :where
             [?country :country/name "United Kingdom"]
             [?country :country/name ?name]]
    :args []}
   {:name "musicbrainz-real-selected-artists-releases"
    :kind :query
    :query '[:find ?artist-name ?release-name
             :in $ [?artist-name ...]
             :where
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args [["The Beatles" "Miles Davis"]]}
   {:name "musicbrainz-real-release-date"
    :kind :query
    :query '[:find ?release-name ?year ?month ?day
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]
             [?release :release/year ?year]
             [?release :release/month ?month]
             [?release :release/day ?day]]
    :args [["Abbey Road" "In a Silent Way" "Bitches Brew"]]}
   {:name "musicbrainz-real-fallback-start-month"
    :kind :query
    :query '[:find ?artist-name ?month
             :in $ [?artist-name ...]
             :where
             [?artist :artist/name ?artist-name]
             [(get-else $ ?artist :artist/startMonth "N/A") ?month]]
    :args [["The Beatles" "Miles Davis"]]}
   {:name "musicbrainz-real-get-some-country"
    :kind :query
    :query '[:find ?attr-ident ?name
             :where
             [?entity :country/name "United Kingdom"]
             [(get-some $ ?entity :country/name :artist/name) [?attr ?name]]
             [?attr :db/ident ?attr-ident]]
    :args []}
   {:name "musicbrainz-real-missing-start-year"
    :kind :query
    :query '[:find ?artist-name
             :where
             [?artist :artist/name ?artist-name]
             [(missing? $ ?artist :artist/startYear)]]
    :args []}
   {:name "musicbrainz-real-dynamic-attr"
    :kind :query
    :query '[:find ?artist-name
             :in $ ?country-name [?reference ...]
             :where
             [?country :country/name ?country-name]
             [?artist ?reference ?country]
             [?artist :artist/name ?artist-name]]
    :args ["United Kingdom" [:artist/country]]}
   {:name "musicbrainz-real-top-duration"
    :kind :query
    :query '[:find (min 2 ?millis) (max 2 ?millis)
             :where
             [?track :track/duration ?millis]]
    :args []}
   {:name "musicbrainz-real-not-beatles-male"
    :kind :query
    :query '[:find ?artist-name
             :where
             [?artist :artist/name "The Beatles"]
             (not [?artist :artist/gender :artist.gender/male])
             [?artist :artist/name ?artist-name]]
    :args []}
   {:name "musicbrainz-real-or-two-artists"
    :kind :query
    :query '[:find ?artist-name
             :where
             (or [?artist :artist/name "The Beatles"]
                 [?artist :artist/name "Miles Davis"])
             [?artist :artist/name ?artist-name]]
    :args []}
   {:name "musicbrainz-real-relation-artist-release"
    :kind :query
    :query '[:find ?artist-name ?release-name
             :in $ [[?artist-name ?release-name]]
             :where
             [?artist :artist/name ?artist-name]
             [?release :release/name ?release-name]
             [?release :release/artists ?artist]]
    :args [[["The Beatles" "Abbey Road"]
            ["Miles Davis" "Bitches Brew"]]]}
   {:name "musicbrainz-real-not-join-release"
    :kind :query
    :query '[:find ?release-name
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]
             (not-join [?release]
                       [?release :release/artists ?artist]
                       [?artist :artist/name "The Beatles"])]
    :args [["Abbey Road" "In a Silent Way"]]}
   {:name "musicbrainz-real-or-join-release"
    :kind :query
    :query '[:find ?release-name
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]
             (or-join [?release]
                      (and [?release :release/artists ?artist]
                           [?artist :artist/name "The Beatles"])
                      [?release :release/year 1969])]
    :args [["Abbey Road" "In a Silent Way"]]}
   {:name "musicbrainz-real-map-beatles-releases"
    :kind :query
    :query '{:find [?release-name]
             :where [[?artist :artist/name "The Beatles"]
                     [?release :release/artists ?artist]
                     [?release :release/name ?release-name]]}
    :args []}
   {:name "musicbrainz-real-keys-beatles-releases"
    :kind :query
    :query '[:find ?artist-name ?release-name
             :keys artist release
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-strs-beatles-releases"
    :kind :query
    :query '[:find ?artist-name ?release-name
             :strs artist release
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-syms-beatles-releases"
    :kind :query
    :query '[:find ?artist-name ?release-name
             :syms artist release
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-rule-track-info"
    :kind :query
    :query '[:find ?track-name ?album ?year
             :in $ % ?artist-name
             :where
             (track-info ?track ?track-name ?artist-name ?album ?year)
             [(< ?year 1970)]]
    :args [musicbrainz-rules "The Beatles"]}
   {:name "musicbrainz-real-rule-short-track"
    :kind :query
    :query '[:find ?track-name ?len
             :in $ % ?max
             :where
             [?artist :artist/name "The Beatles"]
             (short-track ?artist ?track ?len ?max)
             [?track :track/name ?track-name]]
    :args [musicbrainz-rules 200000]}
   {:name "musicbrainz-real-pull-release"
    :kind :query
    :preserve-rows true
    :query '[:find (pull ?release [:release/name :release/year])
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]]
    :args [["Abbey Road" "In a Silent Way"]]}
   {:name "musicbrainz-real-dynamic-pull-release"
    :kind :query
    :preserve-rows true
    :query '[:find (pull ?release pattern)
             :in $ ?artist-name pattern
             :where
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]]
    :args ["Led Zeppelin" [:release/name]]}
   {:name "musicbrainz-real-pull-release-nested"
    :kind :query
    :preserve-rows true
    :query '[:find (pull ?release [:release/gid
                                    :release/name
                                    :release/year
                                    {:release/media [:medium/position
                                                     :medium/trackCount
                                                     {:medium/tracks [:track/position
                                                                      :track/name
                                                                      :track/duration]}]}])
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]]
    :args [["Abbey Road" "In a Silent Way"]]}
   {:name "musicbrainz-real-direct-pull-artist"
    :kind :pull
    :pattern '[:artist/gid :artist/name :artist/startYear]
    :entity [:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]}
   {:name "musicbrainz-real-direct-pull-artist-wildcard"
    :kind :pull
    :strip-db-id true
    :pattern '[*]
    :entity [:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]}
   {:name "musicbrainz-real-direct-pull-artist-releases"
    :kind :pull
    :pattern '[:artist/name {:release/_artists [:release/name :release/year]}]
    :entity [:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]}
   {:name "musicbrainz-real-direct-pull-artist-releases-limit"
    :kind :pull
    :pattern '[:artist/name {(limit :release/_artists 2) [:release/name :release/year]}]
    :entity [:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]}
   {:name "musicbrainz-real-direct-pull-artist-default"
    :kind :pull
    :pattern '[[:artist/gender :default "group"] :artist/name]
    :entity [:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]}
   {:name "musicbrainz-real-direct-pull-artist-alias"
    :kind :pull
    :pattern '[[:artist/name :as :artist] [:artist/gender :default "group" :as :kind]]
    :entity [:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]}
   {:name "musicbrainz-real-direct-pull-many-artists"
    :kind :pull-many
    :pattern '[:artist/gid :artist/name :artist/startYear]
    :entities [[:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]
               [:artist/gid #uuid "561d854a-6a28-4aa7-8c99-323e6ce46c2a"]]}
   {:name "musicbrainz-real-direct-pull-release"
    :kind :pull
    :pattern '[:release/gid
               :release/name
               :release/year
               {:release/media [:medium/position
                                :medium/trackCount
                                {:medium/tracks [:track/position
                                                 :track/name
                                                 :track/duration]}]}]
    :entity [:release/gid #uuid "eca8996a-a637-3259-ba07-d2573c601a1b"]}])

(def uint64-modulus 18446744073709551616N)

(defn fingerprint-text [seed text]
  (reduce
   (fn [hash byte-value]
     (mod (+ (* hash 131) byte-value)
          uint64-modulus))
   seed
   (seq (.toArray (.codePoints text)))))

(defn canonical-text
  ([value]
   (canonical-text value {}))
  ([value options]
  (cond
    (map? value)
    (let [value (if (:strip-db-id options)
                  (dissoc value :db/id)
                  value)]
      (str "{"
           (str/join " "
                     (map (fn [[k v]]
                            (str (canonical-text k options) " " (canonical-text v options)))
                          (sort-by (fn [[k _]] (canonical-text k options)) value)))
           "}"))

    (sequential? value)
    (str "[" (str/join " " (map #(canonical-text % options) value)) "]")

    (set? value)
    (str "#{" (str/join " " (sort (map #(canonical-text % options) value))) "}")

    (instance? java.util.UUID value)
    (str value)

    (or (instance? Double value)
        (instance? Float value))
    (if-let [float-places (:float-places options)]
      (let [scale (Math/pow 10.0 (double float-places))]
        (str "[:vev/float" float-places " "
             (long (Math/round (* (double value) scale)))
             "]"))
      (str "[:vev/float \"" value "\"]"))

    :else
    (pr-str value))))

(defn result-rows [result]
  (cond
    (set? result) result
    (sequential? result) result
    :else [result]))

(defn result-row-count [rows]
  (count rows))

(defn result-row-key [row options]
  (let [values (if (sequential? row) row [row])]
    (str/join "|" (map #(canonical-text % options) values))))

(defn hex64 [value]
  (let [hex (.toString (biginteger value) 16)
        padded (str "0000000000000000" hex)]
    (subs padded (- (count padded) 16))))

(defn result-fingerprint [rows options]
  (hex64
   (reduce
    (fn [hash key]
      (fingerprint-text (fingerprint-text hash key) "\n"))
    0N
    (sort (map #(result-row-key % options) rows)))))

(defn print-result-rows [workload rows options]
  (doseq [key (sort (map #(result-row-key % options) rows))]
    (println (format "row engine=clojure-vev workload=%s key=%s" workload key))))

(defn elapsed-us [f]
  (let [start (System/nanoTime)
        result (f)
        stop (System/nanoTime)]
    [result (/ (- stop start) 1000.0)]))

(defn timing [samples]
  (let [xs (vec (sort samples))
        n (count xs)
        idx (fn [p]
              (min (dec n) (long (Math/floor (* p (dec n))))))]
    {:min (first xs)
     :median (nth xs (idx 0.5))
     :p90 (nth xs (idx 0.9))
     :max (last xs)}))

(defn parse-int-arg [args name default-value]
  (let [idx (.indexOf args name)]
    (if (and (>= idx 0) (< (inc idx) (count args)))
      (Long/parseLong (nth args (inc idx)))
      default-value)))

(defn parse-arg [args name default-value]
  (let [idx (.indexOf args name)]
    (if (and (>= idx 0) (< (inc idx) (count args)))
      (nth args (inc idx))
      default-value)))

(defn should-run? [selected name]
  (or (= selected "all")
      (= selected name)
      (= selected (str/replace name #"^musicbrainz-real-" ""))
      (= selected (str/replace name #"^musicbrainz-smoke-" ""))))

(defn load-tx! [conn path label]
  (let [[report elapsed] (elapsed-us #(vev/transact-text conn (slurp path)))]
    (when (str/includes? report ":ok false")
      (throw (ex-info "Vev tx failed" {:path path :report report})))
    (println
     (format "engine=clojure-vev workload=musicbrainz-real-load ok=true stage=%s tx_us=%.0f"
             label elapsed))))

(defn load-real! [conn schema values values-prefix values-chunks]
  (let [[_ elapsed]
        (elapsed-us
         #(do
            (load-tx! conn schema "schema")
            (if (seq values)
              (load-tx! conn values "values")
              (doseq [index (range values-chunks)]
                (load-tx! conn
                          (format "%s-values-%04d.edn" values-prefix index)
                          (format "values-%04d" index))))))]
    (println
     (format "engine=clojure-vev workload=musicbrainz-real-load ok=true total_us=%.0f"
             elapsed))))

(defn workload-result [db workload prepared-pattern]
  (case (:kind workload)
    :query (if (:preserve-rows workload)
             (apply vev/rows (:query workload) db (:args workload))
             (apply vev/q (:query workload) db (:args workload)))
    :pull [(vev/pull db (or prepared-pattern (:pattern workload)) (:entity workload))]
    :pull-many (vev/pull-many db (or prepared-pattern (:pattern workload)) (:entities workload))))

(defn run-workload [db warmups samples print-rows? workload]
  (let [run (fn [prepared-pattern]
              (dotimes [_ warmups]
                (workload-result db workload prepared-pattern))
              (let [sample-us (doall
                               (for [_ (range samples)]
                                 (second (elapsed-us #(workload-result db workload prepared-pattern)))))
                    result (workload-result db workload prepared-pattern)
                    rows (result-rows result)
                    fingerprint-options {:strip-db-id (:strip-db-id workload)
                                         :float-places (:float-places workload)}
                    t (timing sample-us)]
                (println
                 (format
                  "engine=clojure-vev workload=%s ok=true rows=%d fingerprint=%s min_us=%.0f median_us=%.0f p90_us=%.0f max_us=%.0f"
                  (:name workload)
                  (result-row-count rows)
                  (result-fingerprint rows fingerprint-options)
                  (:min t)
                  (:median t)
                  (:p90 t)
                  (:max t)))
                (when print-rows?
                  (print-result-rows (:name workload) rows fingerprint-options))))]
    (if (or (= :pull (:kind workload))
            (= :pull-many (:kind workload)))
      (with-open [prepared-pattern (vev/prepare-pull-pattern db (:pattern workload))]
        (run prepared-pattern))
      (run nil))))

(defn -main [& raw-args]
  (let [args (vec raw-args)
        lib (parse-arg args "--lib" default-lib)
        uri (parse-arg args "--uri" "")
        schema (parse-arg args "--schema" default-schema)
        values (parse-arg args "--values" default-values)
        values-prefix (parse-arg args "--values-prefix" default-values-prefix)
        values-chunks (parse-int-arg args "--values-chunks" 8)
        selected (parse-arg args "--workload" "country-names")
        warmups (parse-int-arg args "--warmups" 5)
        samples (parse-int-arg args "--samples" 10)
        print-rows? (= (parse-arg args "--print-rows" "false") "true")]
    (if (seq uri)
      (let [[conn open-us] (elapsed-us #(if (seq lib)
                                          (vev/connect lib uri)
                                          (vev/connect uri)))]
        (try
          (println
           (format "engine=clojure-vev workload=musicbrainz-real-open ok=true uri=%s open_us=%.0f info=%s"
                   uri
                   open-us
                   (pr-str (vev/connection-info conn))))
          (with-open [db (vev/db conn)]
            (doseq [workload workloads
                    :when (should-run? selected (:name workload))]
              (run-workload db warmups samples print-rows? workload)))
          (finally
            (.close conn))))
      (with-open [conn (if (seq lib)
                         (vev/create-conn lib)
                         (vev/create-conn))]
        (load-real! conn schema values values-prefix values-chunks)
        (with-open [db (vev/db conn)]
          (doseq [workload workloads
                  :when (should-run? selected (:name workload))]
            (run-workload db warmups samples print-rows? workload)))))))

(apply -main *command-line-args*)
