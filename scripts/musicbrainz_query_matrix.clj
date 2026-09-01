(ns musicbrainz-query-matrix
  (:require [clojure.string :as str]
            [datomic.api :as d]))

(def default-uri "datomic:dev://localhost:4334/mbrainz-1968-1973")

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

(def queries
  [{:name "musicbrainz-real-release-first"
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
    :query '[:find ?release-name
             :where
             [?artist :artist/name "The Beatles"]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-beatles-short-track-collection"
    :result-kind :collection
    :query '[:find [?track-name ...]
             :where
             [?artist :artist/name "The Beatles"]
             [?track :track/artists ?artist]
             [?track :track/name ?track-name]
             [?track :track/duration ?duration]
             [(< ?duration 300000)]]
    :args []}
   {:name "musicbrainz-real-abbey-road-release-date-tuple"
    :result-kind :tuple
    :query '[:find [?year ?month ?day]
             :where
             [?release :release/gid #uuid "eca8996a-a637-3259-ba07-d2573c601a1b"]
             [?release :release/year ?year]
             [?release :release/month ?month]
             [?release :release/day ?day]]
    :args []}
   {:name "musicbrainz-real-beatles-start-year-scalar"
    :result-kind :scalar
    :query '[:find ?year .
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/startYear ?year]]
    :args []}
   {:name "musicbrainz-real-abbey-road-track-minutes"
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
    :query '[:find (count ?track)
             :where
             [?artist :artist/name "The Beatles"]
             [?track :track/artists ?artist]
             [?track :track/name]]
    :args []}
   {:name "musicbrainz-real-beatles-min-max-duration"
    :query '[:find (min ?dur) (max ?dur)
             :where
             [?artist :artist/name "The Beatles"]
             [?track :track/artists ?artist]
             [?track :track/duration ?dur]]
    :args []}
   {:name "musicbrainz-real-beatles-duration-stats"
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
   {:name "musicbrainz-real-track-name-statistics"
    :float-places 6
    :query '[:find ?year (median ?namelen) (avg ?namelen) (stddev ?namelen)
             :with ?track
             :where
             [?track :track/name ?name]
             [(count ?name) ?namelen]
             [?medium :medium/tracks ?track]
             [?release :release/media ?medium]
             [?release :release/year ?year]]
    :args []}
   {:name "musicbrainz-real-lookup-country"
    :query '[:find ?name
             :where
             [?country :country/name "United Kingdom"]
             [?country :country/name ?name]]
    :args []}
   {:name "musicbrainz-real-selected-artists-releases"
    :query '[:find ?artist-name ?release-name
             :in $ [?artist-name ...]
             :where
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args [["The Beatles" "Miles Davis"]]}
   {:name "musicbrainz-real-release-date"
    :query '[:find ?release-name ?year ?month ?day
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]
             [?release :release/year ?year]
             [?release :release/month ?month]
             [?release :release/day ?day]]
    :args [["Abbey Road" "In a Silent Way" "Bitches Brew"]]}
   {:name "musicbrainz-real-fallback-start-month"
    :query '[:find ?artist-name ?month
             :in $ [?artist-name ...]
             :where
             [?artist :artist/name ?artist-name]
             [(get-else $ ?artist :artist/startMonth "N/A") ?month]]
    :args [["The Beatles" "Miles Davis"]]}
   {:name "musicbrainz-real-get-some-country"
    :query '[:find ?attr-ident ?name
             :where
             [?entity :country/name "United Kingdom"]
             [(get-some $ ?entity :country/name :artist/name) [?attr ?name]]
             [?attr :db/ident ?attr-ident]]
    :args []}
   {:name "musicbrainz-real-missing-start-year"
    :query '[:find ?artist-name
             :where
             [?artist :artist/name ?artist-name]
             [(missing? $ ?artist :artist/startYear)]]
    :args []}
   {:name "musicbrainz-real-dynamic-attr"
    :query '[:find ?artist-name
             :in $ ?country-name [?reference ...]
             :where
             [?country :country/name ?country-name]
             [?artist ?reference ?country]
             [?artist :artist/name ?artist-name]]
    :args ["United Kingdom" [:artist/country]]}
   {:name "musicbrainz-real-top-duration"
    :query '[:find (min 2 ?millis) (max 2 ?millis)
             :where
             [?track :track/duration ?millis]]
    :args []}
   {:name "musicbrainz-real-not-beatles-male"
    :query '[:find ?artist-name
             :where
             [?artist :artist/name "The Beatles"]
             (not [?artist :artist/gender :artist.gender/male])
             [?artist :artist/name ?artist-name]]
    :args []}
   {:name "musicbrainz-real-or-two-artists"
    :query '[:find ?artist-name
             :where
             (or [?artist :artist/name "The Beatles"]
                 [?artist :artist/name "Miles Davis"])
             [?artist :artist/name ?artist-name]]
    :args []}
   {:name "musicbrainz-real-relation-artist-release"
    :query '[:find ?artist-name ?release-name
             :in $ [[?artist-name ?release-name]]
             :where
             [?artist :artist/name ?artist-name]
             [?release :release/name ?release-name]
             [?release :release/artists ?artist]]
    :args [[["The Beatles" "Abbey Road"]
            ["Miles Davis" "Bitches Brew"]]]}
   {:name "musicbrainz-real-not-join-release"
    :query '[:find ?release-name
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]
             (not-join [?release]
                       [?release :release/artists ?artist]
                       [?artist :artist/name "The Beatles"])]
    :args [["Abbey Road" "In a Silent Way"]]}
   {:name "musicbrainz-real-or-join-release"
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
    :query '[:find ?release-name
             :where
             [?artist :artist/name "The Beatles"]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-keys-beatles-releases"
    :query '[:find ?artist-name ?release-name
             :keys artist release
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-strs-beatles-releases"
    :query '[:find ?artist-name ?release-name
             :strs artist release
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-syms-beatles-releases"
    :query '[:find ?artist-name ?release-name
             :syms artist release
             :where
             [?artist :artist/name "The Beatles"]
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]
             [?release :release/name ?release-name]]
    :args []}
   {:name "musicbrainz-real-rule-track-info"
    :query '[:find ?track-name ?album ?year
             :in $ % ?artist-name
             :where
             (track-info ?track ?track-name ?artist-name ?album ?year)
             [(< ?year 1970)]]
    :args [musicbrainz-rules "The Beatles"]}
   {:name "musicbrainz-real-rule-short-track"
    :query '[:find ?track-name ?len
             :in $ % ?max
             :where
             [?artist :artist/name "The Beatles"]
             (short-track ?artist ?track ?len ?max)
             [?track :track/name ?track-name]]
    :args [musicbrainz-rules 200000]}
   {:name "musicbrainz-real-pull-release"
    :query '[:find (pull ?release [:release/name :release/year])
             :in $ [?release-name ...]
             :where
             [?release :release/name ?release-name]]
    :args [["Abbey Road" "In a Silent Way"]]}
   {:name "musicbrainz-real-dynamic-pull-release"
    :query '[:find (pull ?release pattern)
             :in $ ?artist-name pattern
             :where
             [?artist :artist/name ?artist-name]
             [?release :release/artists ?artist]]
    :args ["Led Zeppelin" [:release/name]]}
   {:name "musicbrainz-real-pull-release-nested"
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
    :pattern '[*]
    :entity [:artist/gid #uuid "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"]
    :strip-db-id true}
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
(def fingerprint-seed 0N)

(defn fingerprint-text [seed text]
  (reduce
   (fn [hash byte-value]
     (mod (+ (* hash 131) byte-value)
          uint64-modulus))
   seed
   (seq (.toArray (.codePoints text)))))

(defn canonical-text-with-options [value {:keys [strip-db-id float-places] :as options}]
  (cond
    (map? value)
    (str "{"
         (str/join " "
                   (map (fn [[k v]]
                          (str (canonical-text-with-options k options)
                               " "
                               (canonical-text-with-options v options)))
                        (sort-by
                         (comp #(canonical-text-with-options % options) key)
                         (if strip-db-id
                           (dissoc value :db/id)
                           value))))
         "}")

    (sequential? value)
    (str "[" (str/join " " (map #(canonical-text-with-options % {:strip-db-id strip-db-id}) value)) "]")

    (set? value)
    (str "#{" (str/join " " (sort (map #(canonical-text-with-options % {:strip-db-id strip-db-id}) value))) "}")

    (instance? java.util.UUID value)
    (str value)

    (or (instance? Double value)
        (instance? Float value))
    (if float-places
      (let [scale (Math/pow 10.0 (double float-places))]
        (str "[:vev/float" float-places " "
             (long (Math/round (* (double value) scale)))
             "]"))
      (str "[:vev/float \"" value "\"]"))

    :else
    (pr-str value)))

(defn canonical-text [value]
  (canonical-text-with-options value {:strip-db-id false}))

(defn result-row-key-with-options [row options]
  (let [values (if (sequential? row) row [row])]
    (str/join "|" (map #(canonical-text-with-options % options) values))))

(defn result-row-key [row]
  (result-row-key-with-options row {:strip-db-id false}))

(defn result-rows [result result-kind]
  (case result-kind
    :tuple (if (seq result) [result] [])
    :scalar [result]
    result))

(defn result-fingerprint-with-options [rows options]
  (let [hash (reduce
              (fn [hash key]
                (fingerprint-text (fingerprint-text hash key) "\n"))
              fingerprint-seed
              (sort (map #(result-row-key-with-options % options) rows)))
        hex (.toString (biginteger hash) 16)]
    (str (apply str (repeat (max 0 (- 16 (count hex))) "0"))
         hex)))

(defn result-fingerprint [rows]
  (result-fingerprint-with-options rows {:strip-db-id false}))

(defn result-row-count [rows]
  (count rows))

(defn elapsed-us [f]
  (let [start (System/nanoTime)
        result (f)
        elapsed (/ (double (- (System/nanoTime) start)) 1000.0)]
    [result elapsed]))

(defn timing [samples]
  (let [xs (vec (sort samples))
        n (count xs)
        idx (fn [p]
              (min (dec n) (long (Math/floor (* p (dec n))))))]
    {:min (first xs)
     :median (nth xs (idx 0.5))
     :p90 (nth xs (idx 0.9))
     :max (last xs)}))

(defn print-result-rows-with-options [workload rows options]
  (doseq [key (sort (map #(result-row-key-with-options % options) rows))]
    (println (format "row engine=datomic workload=%s key=%s" workload key))))

(defn print-result-rows [workload rows]
  (print-result-rows-with-options workload rows {:strip-db-id false}))

(defn workload-fingerprint-options [workload]
  {:strip-db-id (boolean (:strip-db-id workload))
   :float-places (:float-places workload)})

(defn run-query [db warmups samples print-rows? {:keys [name query args result-kind] :as workload}]
  (dotimes [_ warmups]
    (apply d/q query db args))
  (let [sample-us (doall
                   (for [_ (range samples)]
                     (second (elapsed-us #(apply d/q query db args)))))
        result (apply d/q query db args)
        rows (result-rows result result-kind)
        options (workload-fingerprint-options workload)
        t (timing sample-us)]
    (println
     (format
      "engine=datomic workload=%s ok=true rows=%d fingerprint=%s min_us=%.0f median_us=%.0f p90_us=%.0f max_us=%.0f"
      name
      (result-row-count rows)
      (result-fingerprint-with-options rows options)
      (:min t)
      (:median t)
      (:p90 t)
      (:max t)))
    (when print-rows?
      (print-result-rows-with-options name rows options))))

(defn workload-result [db {:keys [kind query args pattern entity entities]}]
  (case kind
    :pull [(d/pull db pattern entity)]
    :pull-many (d/pull-many db pattern entities)
    (apply d/q query db args)))

(defn run-workload [db warmups samples print-rows? workload]
  (if (:kind workload)
    (let [name (:name workload)
          options (workload-fingerprint-options workload)]
      (dotimes [_ warmups]
        (workload-result db workload))
      (let [sample-us (doall
                       (for [_ (range samples)]
                         (second (elapsed-us #(workload-result db workload)))))
            result (workload-result db workload)
            rows (result-rows result (:result-kind workload))
            t (timing sample-us)]
        (println
         (format
          "engine=datomic workload=%s ok=true rows=%d fingerprint=%s min_us=%.0f median_us=%.0f p90_us=%.0f max_us=%.0f"
          name
          (result-row-count rows)
          (result-fingerprint-with-options rows options)
          (:min t)
          (:median t)
          (:p90 t)
          (:max t)))
        (when print-rows?
          (print-result-rows-with-options name rows options))))
    (run-query db warmups samples print-rows? workload)))

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
      (= selected (str/replace name #"^musicbrainz-real-" ""))))

(defn -main [& raw-args]
  (let [args (vec raw-args)
        uri (parse-arg args "--uri" default-uri)
        selected (parse-arg args "--workload" "all")
        warmups (parse-int-arg args "--warmups" 5)
        samples (parse-int-arg args "--samples" 10)
        print-rows? (= (parse-arg args "--print-rows" "false") "true")
        conn (d/connect uri)
        db (d/db conn)]
    (doseq [query queries
            :when (should-run? selected (:name query))]
      (run-workload db warmups samples print-rows? query))
    (shutdown-agents)
    (System/exit 0)))

(apply -main *command-line-args*)
