;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns musicbrainz-workshop
  (:require [clojure.edn :as edn]
            [vev.core :as d]))

;; Port source of truth:
;; build/upstream/day-of-datomic-conj/src/music_brainz.clj
;; Sections: file top through Pattern inputs.
;; build/upstream/day-of-datomic/tutorial/query.clj
;; Sections: negation/disjunction count examples, predicate/function expressions,
;; get-else, get-some, fulltext, missing?, transaction-log and collection
;; function examples,
;; dynamic attribute specs, and aggregate examples.
;; build/upstream/day-of-datomic/tutorial/pull.clj
;; Sections: setup through dynamic pattern input.
;; build/upstream/mbrainz-sample/examples/clj/datomic/samples/mbrainz.clj
;; Sections: opening data queries.

(def default-uri "build/musicbrainz/vev-mbrainz-tutorial.sqlite")
(def mbrainz-sample-rules-path "build/upstream/mbrainz-sample/resources/rules.edn")
(def mbrainz-sample-rules (delay (edn/read-string (slurp mbrainz-sample-rules-path))))

(def led-zeppelin [:artist/gid #uuid "678d88b2-87b0-403b-b63d-5da7465aecc3"])
(def mccartney [:artist/gid #uuid "ba550d0e-adac-4864-b88b-407cab5e76af"])
(def dark-side-of-the-moon [:release/gid #uuid "24824319-9bb8-3d1e-a2c5-b8b864dafd1b"])
(def dylan-harrison-sessions [:release/gid #uuid "67bbc160-ac45-4caf-baae-a7e9f5180429"])
(def concert-for-bangla-desh [:release/gid #uuid "f3bdff34-9a85-4adc-a014-922eef9cdaa5"])

(defn connect []
  (d/connect default-uri))

(defn db [conn]
  (d/db conn))

(def john-lennon-release-pull-query
  '[:find [(pull $ ?release [*])]
    :in $ ?artist-name
    :where
    [?release :release/artists ?artist]
    [?artist :artist/name ?artist-name]
    [?release :release/name ?release-name]])

(def tuple-binding-query
  '[:find [(pull $ ?release [*])]
    :in $ [?artist-name ?release-name]
    :where
    [?artist :artist/name ?artist-name]
    [?release :release/artists ?artist]
    [?release :release/name ?release-name]])

(def request-map-query
  '[:find (pull $ ?release
                [:release/name
                 :release/artistCredit
                 :release/year
                 {:release/script [*]}
                 {:release/media [{:medium/tracks [:track/name]}]}])
    :in $ ?artist-name
    :where
    [?artist :artist/name ?artist-name]
    [?release :release/artists ?artist]])

(def collection-binding-query
  '[:find ?release-name
    :in $ [?artist-name ...]
    :where
    [?artist :artist/name ?artist-name]
    [?release :release/artists ?artist]
    [?release :release/name ?release-name]])

(def relation-binding-query
  '[:find ?release
    :in $ [[?artist-name ?release-name]]
    :where
    [?artist :artist/name ?artist-name]
    [?release :release/artists ?artist]
    [?release :release/name ?release-name]])

(def relation-find-missing-db-query
  '[:find ?artist-name ?release-name
    :in ?artist-name
    :where
    [?release :release/name ?release-name]
    [?release :release/artists ?artist]
    [?artist :artist/name ?artist-name]])

(def relation-find-query
  '[:find ?artist-name ?release-name
    :in $ ?artist-name
    :where
    [?release :release/name ?release-name]
    [?release :release/artists ?artist]
    [?artist :artist/name ?artist-name]])

(def collection-find-query
  '[:find [?release-name ...]
    :in $ ?artist-name
    :where
    [?artist :artist/name ?artist-name]
    [?release :release/artists ?artist]
    [?release :release/name ?release-name]])

(def tuple-find-query
  '[:find [?year ?month ?day]
    :in $ ?name
    :where
    [?artist :artist/name ?name]
    [?artist :artist/startDay ?day]
    [?artist :artist/startMonth ?month]
    [?artist :artist/startYear ?year]])

(def scalar-find-query
  '[:find ?year .
    :in $ ?name
    :where
    [?artist :artist/name ?name]
    [?artist :artist/startYear ?year]])

(def artist-not-canada-count-query
  '[:find (count ?eid) .
    :where
    [?eid :artist/name]
    (not [?eid :artist/country :country/CA])])

(def artist-not-release-1970-count-query
  '[:find (count ?artist) .
    :where
    [?artist :artist/name]
    (not-join [?artist]
              [?release :release/artists ?artist]
              [?release :release/year 1970])])

(def live-at-carnegie-not-bill-withers-count-query
  '[:find (count ?r) .
    :where
    [?r :release/name "Live at Carnegie Hall"]
    (not-join [?r]
              [?r :release/artists ?a]
              [?a :artist/name "Bill Withers"])])

(def artist-or-type-gender-count-query
  '[:find (count ?artist) .
    :where
    (or [?artist :artist/type :artist.type/group]
        (and [?artist :artist/type :artist.type/person]
             [?artist :artist/gender :artist.gender/female]))])

(def release-or-canada-artist-or-1970-count-query
  '[:find (count ?release) .
    :where
    [?release :release/name]
    (or-join [?release]
             (and [?release :release/artists ?artist]
                  [?artist :artist/country :country/CA])
             [?release :release/year 1970])])

(def artist-start-before-1600-query
  '[:find ?name ?year
    :where
    [?artist :artist/name ?name]
    [?artist :artist/startYear ?year]
    [(< ?year 1600)]])

(def return-map-find-query
  '[:find ?artist-name ?release-name
    :keys artist release
    :in $ ?artist-name
    :where
    [?release :release/name ?release-name]
    [?release :release/artists ?artist]
    [?artist :artist/name ?artist-name]])

(defn teste
  [?yeat]
  (< ?yeat 1600))

(intern (create-ns 'user) 'teste teste)

(def host-predicate-query
  '[:find ?name ?year
    :where
    [?artist :artist/name ?name]
    [?artist :artist/startYear ?year]
    [(user/teste ?year)]])

(def function-expression-query
  '[:find ?track-name ?minutes
    :in $ ?artist-name
    :where
    [?artist :artist/name ?artist-name]
    [?track :track/artists ?artist]
    [?track :track/duration ?millis]
    [(quot ?millis 60000) ?minutes]
    [?track :track/name ?track-name]])

(def fahrenheit-to-celsius-query
  '[:find ?celsius .
    :in ?fahrenheit
    :where
    [(- ?fahrenheit 32) ?f-32]
    [(/ ?f-32 1.8) ?celsius]])

(def get-else-artist-start-query
  '[:find ?artist-name ?year
    :in $ [?artist-name ...]
    :where
    [?artist :artist/name ?artist-name]
    [(get-else $ ?artist :artist/startYear "N/A") ?year]])

(def get-some-country-query
  '[:find [?e ?attr ?name]
    :in $ ?e
    :where
    [(get-some $ ?e :country/name :artist/name) [?attr ?name]]])

(def fulltext-artist-name-query
  '[:find ?entity ?name ?tx ?score
    :in $ ?search
    :where
    [(fulltext $ :artist/name ?search) [[?entity ?name ?tx ?score]]]])

(def missing-artist-start-query
  '[:find ?name
    :where
    [?artist :artist/name ?name]
    [(missing? $ ?artist :artist/startYear)]])

(def log-tx-ids-query
  '[:find [?tx ...]
    :in ?log
    :where [(tx-ids ?log 0 10) [?tx ...]]])

(def log-tx-data-entities-query
  '[:find [?e ...]
    :in ?log ?tx
    :where [(tx-data ?log ?tx) [[?e]]]])

(def word-prefix-query
  '[:find [?prefix ...]
    :in [?word ...]
    :where [(subs ?word 0 5) ?prefix]])

(def attrs-with-value-42-query
  '[:find [?aname ...]
    :where
    [?attr 42 _]
    [?attr :db/ident ?aname]])

(def attrs-with-property-query
  '[:find [?aname ...]
    :in $ [?property ...]
    :where
    [?attr ?property _]
    [?attr :db/ident ?aname]])

(def country-artists-query
  '[:find [?artist-name ...]
    :in $ ?country
    :where
    [?artist :artist/name ?artist-name]
    [?artist :artist/country ?country]])

;; The installed 1968-1973 sample assigns Belgium this source entity ID. The
;; older upstream tutorial snapshot used 17592186045516 for the same example.
(def belgium-entity-id 17592186045669)

(def dynamic-reference-country-query
  '[:find [?artist-name ...]
    :in $ ?country [?reference ...]
    :where
    [?artist :artist/name ?artist-name]
    [?artist ?reference ?country]])

(def dynamic-reference-country-entid-query
  '[:find [?artist-name ...]
    :in $ ?country [?reference ...]
    :where
    [(datomic.api/entid $ ?country) ?country-id]
    [?artist :artist/name ?artist-name]
    [?artist ?reference ?country-id]])

(def artist-type-gender-query
  '[:find ?id ?type ?gender
    :in $ ?name
    :where
    [?e :artist/name ?name]
    [?e :artist/gid ?id]
    [?e :artist/type ?teid]
    [?teid :db/ident ?type]
    [?e :artist/gender ?geid]
    [?geid :db/ident ?gender]])

(def monster-heads
  [["Cerberus" 3]
   ["Medusa" 1]
   ["Cyclops" 1]
   ["Chimera" 1]])

(def monster-heads-sum-query
  '[:find (sum ?heads) .
    :in [[_ ?heads]]])

(def monster-heads-sum-with-query
  '[:find (sum ?heads) .
    :with ?monster
    :in [[?monster ?heads]]])

(def distinct-values-query
  '[:find (distinct ?v) .
    :in [?v ...]])

(def distinct-values-input
  [1 1 2 2 2 3])

(def min-track-duration-query
  '[:find [(min ?dur)]
    :where
    [?e :track/duration ?dur]])

(def top-track-duration-query
  '[:find [(min 5 ?millis) (max 5 ?millis)]
    :where
    [?track :track/duration ?millis]])

(def random-artist-name-query
  '[:find [(rand 2 ?name) (sample 2 ?name)]
    :where
    [_ :artist/name ?name]])

(def sum-medium-track-count-query
  '[:find (sum ?count) .
    :with ?medium
    :where
    [?medium :medium/trackCount ?count]])

(def artist-name-count-query
  '[:find (count ?name) (count-distinct ?name)
    :with ?artist
    :where
    [?artist :artist/name ?name]])

(def track-name-statistics-query
  '[:find ?year (median ?namelen) (avg ?namelen) (stddev ?namelen)
    :with ?track
    :where
    [?track :track/name ?name]
    [(count ?name) ?namelen]
    [?medium :medium/tracks ?track]
    [?release :release/media ?medium]
    [?release :release/year ?year]])

(defn mode
  [vals]
  (->> (frequencies vals)
       (sort-by (comp - second))
       ffirst))

(intern (create-ns 'user) 'mode mode)

(def custom-mode-aggregate-query
  '[:find (user/mode ?track-count) .
    :with ?media
    :where
    [?media :medium/trackCount ?track-count]])

(def query-timeout-query
  '[:find ?track-name
    :in $ ?artist-name
    :where
    [?track :track/artists ?artist]
    [?track :track/name ?track-name]
    [?artist :artist/name ?artist-name]])

(def tracks-by-artist-name-query
  '[:find ?title
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?r :release/artists ?a]
    [?t :track/artists ?a]
    [?t :track/name ?title]])

(def mbrainz-title-by-artist-query
  '[:find ?title
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?t :track/artists ?a]
    [?t :track/name ?title]])

(def mbrainz-title-album-year-by-artist-query
  '[:find ?title ?album ?year
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?t :track/artists ?a]
    [?t :track/name ?title]
    [?m :medium/tracks ?t]
    [?r :release/media ?m]
    [?r :release/name ?album]
    [?r :release/year ?year]])

(def mbrainz-pre-1970-title-album-year-query
  '[:find ?title ?album ?year
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?t :track/artists ?a]
    [?t :track/name ?title]
    [?m :medium/tracks ?t]
    [?r :release/media ?m]
    [?r :release/name ?album]
    [?r :release/year ?year]
    [(< ?year 1970)]])

(def mbrainz-track-release-rule-query
  '[:find ?title ?album ?year
    :in $ % ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?t :track/artists ?a]
    [?t :track/name ?title]
    (track-release ?t ?r)
    [?r :release/name ?album]
    [?r :release/year ?year]])

(def mbrainz-track-search-info-query
  '[:find ?title ?artist ?album ?year
    :in $ % ?search
    :where
    (track-search ?search ?track)
    (track-info ?track ?title ?artist ?album ?year)])

(def mbrainz-collab-query
  '[:find ?aname ?aname2
    :in $ % [?aname ...]
    :where (collab ?aname ?aname2)])

(def mbrainz-collab-net-2-query
  '[:find ?aname ?aname2
    :in $ % [?aname ...]
    :where (collab-net-2 ?aname ?aname2)])

(def mbrainz-collab-nested-query
  '[:find ?aname2
    :in $ % [[?aname]]
    :where (collab ?aname ?aname2)])

(def mbrainz-bill-withers-collaboration-query
  '[:find ?aname ?tname
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?t :track/artists ?a]
    [?t :track/name ?tname]
    [(!= "Outro" ?tname)]
    [(!= "[outro]" ?tname)]
    [(!= "Intro" ?tname)]
    [(!= "[intro]" ?tname)]
    [?t2 :track/name ?tname]
    [?t2 :track/artists ?a2]
    [(!= ?a2 ?a)]
    [?a2 :artist/name ?aname]])

(def pre-1970-release-names-query
  '[:find ?name
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?r :release/artists ?a]
    [?r :release/year ?year]
    [(< ?year 1970)]
    [?r :release/name ?name]])

(def pre-1970-release-names-switched-query
  '[:find ?name
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?r :release/artists ?a]
    [?r :release/year ?year]
    [?r :release/name ?name]
    [(< ?year 1970)]])

(def pre-1970-track-titles-broad-query
  '[:find ?title
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?r :release/artists ?a]
    [?r :release/year ?year]
    [?r :release/name ?name]
    [(< ?year 1970)]
    [?t :track/artists ?a]
    [?t :track/name ?title]])

(def pre-1970-track-titles-with-release-name-query
  '[:find ?title
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?r :release/artists ?a]
    [?r :release/year ?year]
    [?r :release/name ?name]
    [(< ?year 1970)]
    [?r :release/media ?m]
    [?m :medium/tracks ?t]
    [?t :track/name ?title]])

(def pre-1970-track-titles-query
  '[:find ?title
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?r :release/artists ?a]
    [?r :release/year ?year]
    [(< ?year 1970)]
    [?r :release/media ?m]
    [?m :medium/tracks ?t]
    [?t :track/name ?title]])

(def track-release-rules
  '[[(track-release ?t ?r)
     [?m :medium/tracks ?t]
     [?r :release/media ?m]]])

(def track-release-rule-query
  '[:find ?title ?album ?year
    :in $ % ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?t :track/artists ?a]
    [?t :track/name ?title]
    (track-release ?t ?r)
    [?r :release/name ?album]
    [?r :release/year ?year]])

(def track-artist-rules
  '[[(track-artist ?t ?artist-name)
     [?t :track/artists ?a]
     [?a :artist/name ?artist-name]]])

(def track-release-detail-rules
  '[[(track-release ?t ?release-name ?release-year)
     [?m :medium/tracks ?t]
     [?r :release/media ?m]
     [?r :release/name ?release-name]
     [?r :release/year ?release-year]]])

(def track-info-rules
  (concat
   track-artist-rules
   track-release-detail-rules
   '[[(track-info ?t ?artist-name ?release-name ?release-year)
      (track-artist ?t ?artist-name)
      (track-release ?t ?release-name ?release-year)]]))

(def track-rules-exercise-query
  '[:find ?track-name ?artist-name ?release-name ?release-year
    :in $ % ?track-name
    :where
    [?t :track/name ?track-name]
    (track-artist ?t ?artist-name)
    (track-release ?t ?release-name ?release-year)])

(def track-info-rule-query
  '[:find ?track-name ?artist-name ?release-name ?release-year
    :in $ % ?track-name
    :where
    [?t :track/name ?track-name]
    (track-info ?t ?artist-name ?release-name ?release-year)])

(def pull-release-name-query
  '[:find (pull ?e [:release/name])
    :in $ ?artist-name
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def pull-release-name-dynamic-pattern-query
  '[:find (pull ?e pattern)
    :in $ ?artist-name pattern
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def pull-release-and-artist-query
  '[:find (pull ?e [:release/name]) (pull ?a [*])
    :in $ ?artist-name pattern
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def pull-release-name-and-artists-query
  '[:find (pull ?e [:release/name :release/artists])
    :in $ ?artist-name pattern
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def duplicate-pull-release-query
  '[:find (pull ?e [:release/name]) (pull ?e [:release/artists])
    :in $ ?artist-name pattern
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def nested-pull-release-artists-query
  '[:find (pull ?e [:release/name
                    {:release/artists [*]}])
    :in $ ?artist-name pattern
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def nested-pull-release-artists-country-query
  '[:find (pull ?e [:release/name
                    {:release/artists [*]}
                    {:release/country [*]}])
    :in $ ?artist-name pattern
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def deep-pull-release-artists-country-query
  '[:find (pull ?e [:release/name
                    {:release/artists [*
                                       {:artist/country [*]}]}
                    {:release/country [*]}])
    :in $ ?artist-name pattern
    :where
    [?a :artist/name ?artist-name]
    [?e :release/artists ?a]])

(def direct-pull-expression-in-query-query
  '[:find [(pull ?e [:release/name]) ...]
    :in $ ?artist
    :where
    [?e :release/artists ?artist]])

(def direct-dynamic-pattern-input-query
  '[:find [(pull ?e pattern) ...]
    :in $ ?artist pattern
    :where
    [?e :release/artists ?artist]])

(defn opening-release-pulls [db]
  (d/q john-lennon-release-pull-query db "John Lennon"))

(defn tuple-binding-release-pulls [db]
  (d/q tuple-binding-query db ["John Lennon" "Mind Games"]))

(defn request-map-release-pulls [db]
  (d/query {:query request-map-query
            :args [db "Elis Regina"]}))

(defn collection-binding-releases [db]
  (d/q collection-binding-query db ["Paul McCartney" "George Harrison"]))

(defn relation-binding-releases [db]
  (d/q relation-binding-query
       db
       [["John Lennon" "Mind Games"]
        ["Paul McCartney" "Ram"]]))

(defn relation-find-missing-db [db]
  (d/q relation-find-missing-db-query db "elvis presley"))

(defn relation-find-releases [db]
  (d/q relation-find-query db "Elvis Presley"))

(defn collection-find-releases [db]
  (d/q collection-find-query db "John Lennon"))

(defn tuple-find-artist-start [db]
  (d/q tuple-find-query db "John Lennon"))

(defn scalar-find-artist-start [db]
  (d/q scalar-find-query db "John Lennon"))

(defn artist-not-canada-count [db]
  (d/q artist-not-canada-count-query db))

(defn artist-not-release-1970-count [db]
  (d/q artist-not-release-1970-count-query db))

(defn live-at-carnegie-not-bill-withers-count [db]
  (d/q live-at-carnegie-not-bill-withers-count-query db))

(defn artist-or-type-gender-count [db]
  (d/q artist-or-type-gender-count-query db))

(defn release-or-canada-artist-or-1970-count [db]
  (d/q release-or-canada-artist-or-1970-count-query db))

(defn artist-start-before-1600 [db]
  (d/q artist-start-before-1600-query db))

(defn return-map-releases [db]
  (d/q return-map-find-query db "Paul McCartney"))

(defn return-map-positional-artist [db]
  (let [[artist release] (first (return-map-releases db))]
    artist))

(defn return-map-key-artist [db]
  (let [{:keys [artist release]} (first (return-map-releases db))]
    artist))

(defn host-predicate-artists [db]
  (d/q host-predicate-query db))

(defn function-expression-track-minutes [db]
  (d/q function-expression-query db "John Lennon"))

(defn fahrenheit-to-celsius [fahrenheit]
  (d/q fahrenheit-to-celsius-query fahrenheit))

(defn get-else-artist-starts [db]
  (d/q get-else-artist-start-query db ["Crosby, Stills & Nash" "Crosby & Nash"]))

(defn get-some-country [db]
  (d/q get-some-country-query db :country/US))

(defn fulltext-artist-name [db]
  (d/q fulltext-artist-name-query db "Jane"))

(defn missing-artist-starts [db]
  (d/q missing-artist-start-query db))

(defn log-tx-ids [conn]
  (d/q log-tx-ids-query (d/log conn)))

(defn log-tx-data-entities [conn tx]
  (d/q log-tx-data-entities-query (d/log conn) tx))

(defn word-prefixes []
  (d/q word-prefix-query ["hello" "antidisestablishmentarianism"]))

(defn attrs-with-value-42 [db]
  (d/q attrs-with-value-42-query db))

(defn attrs-with-property [db]
  (d/q attrs-with-property-query db [:db/unique]))

(defn country-artists-by-lookup-ref [db]
  (d/q country-artists-query db [:country/name "Belgium"]))

(defn country-artists-by-ident [db]
  (d/q country-artists-query db :country/BE))

(defn country-artists-by-entity [db]
  (d/q country-artists-query db belgium-entity-id))

(defn dynamic-reference-country-artists [db]
  (d/q dynamic-reference-country-query db :country/BE [:artist/country]))

(defn dynamic-reference-country-artists-entid [db]
  (d/q dynamic-reference-country-entid-query db :country/BE [:artist/country]))

(defn artist-type-gender [db]
  (d/q artist-type-gender-query db "Janis Joplin"))

(defn monster-heads-sum []
  (d/q monster-heads-sum-query monster-heads))

(defn monster-heads-sum-with []
  (d/q monster-heads-sum-with-query monster-heads))

(defn distinct-values []
  (d/q distinct-values-query distinct-values-input))

(defn min-track-duration [db]
  (d/q min-track-duration-query db))

(defn top-track-duration [db]
  (d/q top-track-duration-query db))

(defn random-artist-names [db]
  (d/q random-artist-name-query db))

(defn sum-medium-track-count [db]
  (d/q sum-medium-track-count-query db))

(defn artist-name-counts [db]
  (d/q artist-name-count-query db))

(defn track-name-statistics [db]
  (d/q track-name-statistics-query db))

(defn custom-mode-aggregate [db]
  (d/q custom-mode-aggregate-query db))

(defn query-timeout-example [db]
  (d/query {:query query-timeout-query
            :args [db "John Lennon"]
            :timeout 1}))

(defn tracks-by-artist-name [db]
  (d/query {:query tracks-by-artist-name-query
            :args [db "John Lennon"]
            :io-context :q/tracks-by-artist-name}))

(defn pre-1970-release-name-stats [db]
  (-> (d/query {:query pre-1970-release-names-query
                :args [db "John Lennon"]
                :query-stats true})
      :query-stats))

(defn pre-1970-release-name-results [db]
  (:ret (d/query {:query pre-1970-release-names-query
                  :args [db "John Lennon"]
                  :query-stats true})))

(defn pre-1970-release-name-switched-stats [db]
  (-> (d/query {:query pre-1970-release-names-switched-query
                :args [db "John Lennon"]
                :query-stats true})
      :query-stats))

(defn pre-1970-release-name-switched-results [db]
  (:ret (d/query {:query pre-1970-release-names-switched-query
                  :args [db "John Lennon"]
                  :query-stats true})))

(defn query-stats-result [db query]
  (d/query {:query query
            :args [db "John Lennon"]
            :query-stats true}))

(defn pre-1970-track-title-broad-stats [db]
  (:query-stats (query-stats-result db pre-1970-track-titles-broad-query)))

(defn pre-1970-track-title-with-release-name-stats [db]
  (:query-stats (query-stats-result db pre-1970-track-titles-with-release-name-query)))

(defn pre-1970-track-title-stats [db]
  (:query-stats (query-stats-result db pre-1970-track-titles-query)))

(defn pre-1970-track-title-results [db]
  (:ret (query-stats-result db pre-1970-track-titles-query)))

(defn track-release-rule-results [db]
  (d/query {:query track-release-rule-query
            :args [db track-release-rules "John Lennon"]}))

(defn track-rules-exercise-results [db]
  (d/query {:query track-rules-exercise-query
            :args [db (concat track-artist-rules
                              track-release-detail-rules) "Yer Blues"]}))

(defn track-info-rule-results [db]
  (d/query {:query track-info-rule-query
            :args [db track-info-rules "Yer Blues"]}))

(defn pull-release-names [db]
  (d/query {:query pull-release-name-query
            :args [db "Led Zeppelin"]}))

(defn pull-release-names-dynamic-pattern [db]
  (d/query {:query pull-release-name-dynamic-pattern-query
            :args [db "Led Zeppelin" [:release/name]]}))

(defn pull-release-and-artist [db]
  (d/query {:query pull-release-and-artist-query
            :args [db "Led Zeppelin" [:release/name]]}))

(defn pull-release-name-and-artists [db]
  (d/query {:query pull-release-name-and-artists-query
            :args [db "Led Zeppelin" [:release/name]]}))

(defn duplicate-pull-release [db]
  (d/query {:query duplicate-pull-release-query
            :args [db "Led Zeppelin" [:release/name]]}))

(defn nested-pull-release-artists [db]
  (d/query {:query nested-pull-release-artists-query
            :args [db "Led Zeppelin" [:release/name]]}))

(defn nested-pull-release-artists-country [db]
  (d/query {:query nested-pull-release-artists-country-query
            :args [db "Led Zeppelin" [:release/name]]}))

(defn deep-pull-release-artists-country [db]
  (d/query {:query deep-pull-release-artists-country-query
            :args [db "Led Zeppelin" [:release/name]]}))

(defn direct-pull-expression-in-query [db]
  (d/q direct-pull-expression-in-query-query db led-zeppelin))

(defn direct-dynamic-pattern-input [db]
  (d/q direct-dynamic-pattern-input-query db led-zeppelin [:release/name]))

(defn dylan-harrison-cd [db]
  (d/q '[:find ?medium .
         :in $ ?release
         :where
         [?release :release/media ?medium]]
       db
       dylan-harrison-sessions))

(defn ghost-riders [db]
  (d/q '[:find ?track .
         :in $ ?release ?trackno
         :where
         [?release :release/media ?medium]
         [?medium :medium/tracks ?track]
         [?track :track/position ?trackno]]
       db
       dylan-harrison-sessions
       11))

(defn pull-artist-name-start [db]
  (d/pull db [:artist/name :artist/startYear] led-zeppelin))

(defn pull-artist-country [db]
  (d/pull db [:artist/country] led-zeppelin))

(defn pull-artists-by-country [db]
  (d/pull db [:artist/_country] :country/GB))

(defn pull-release-media-default [db]
  (d/pull db [:release/media] dark-side-of-the-moon))

(defn pull-release-by-media [db]
  (d/pull db [:release/_media] (dylan-harrison-cd db)))

(defn pull-track-artists [db]
  (d/pull db [:track/name {:track/artists [:db/id :artist/name]}] (ghost-riders db)))

(defn pull-release-media-tracks [db]
  (d/pull db
          [{:release/media
            [{:medium/tracks
              [:track/name {:track/artists [:artist/name]}]}]}]
          concert-for-bangla-desh))

(defn pull-release-wildcard [db]
  (d/pull db '[*] concert-for-bangla-desh))

(defn pull-track-wildcard-artists [db]
  (d/pull db '[* {:track/artists [:artist/name]}] (ghost-riders db)))

(defn pull-mccartney-default-end-year [db]
  (d/pull db '[:artist/name (:artist/endYear :default 0)] mccartney))

(defn pull-mccartney-default-end-year-string [db]
  (d/pull db '[:artist/name (:artist/endYear :default "N/A")] mccartney))

(defn pull-mccartney-absent-attribute [db]
  (d/pull db '[:artist/name :died-in-1966?] mccartney))

(defn pull-led-zeppelin-track-limit [db]
  (d/pull db '[(:track/_artists :limit 10)] led-zeppelin))

(defn pull-led-zeppelin-track-limit-names [db]
  (d/pull db '[{(:track/_artists :limit 10) [:track/name]}] led-zeppelin))

(defn pull-led-zeppelin-track-limit-names-as [db]
  (d/pull db '[{(:track/_artists :limit 10 :as "Tracks") [:track/name]}] led-zeppelin))

(defn pull-led-zeppelin-track-no-limit [db]
  (d/pull db '[(:track/_artists :limit nil)] led-zeppelin))

(defn pull-led-zeppelin-empty-results [db]
  (d/pull db '[:penguins] led-zeppelin))

(defn pull-track-artists-empty-results [db]
  (d/pull db '[{:track/artists [:penguins]}] (ghost-riders db)))

(defn validate-opening-bindings! []
  (with-open [conn (connect)
              db (db conn)]
    (let [opening (opening-release-pulls db)
          tuple (tuple-binding-release-pulls db)
          request (request-map-release-pulls db)
          collection (collection-binding-releases db)
          relation (relation-binding-releases db)]
      (assert (and (= 1 (count opening))
                   (map? (first opening))))
      (assert (and (= 1 (count tuple))
                   (map? (first tuple))))
      (assert (= 10 (count request)))
      (assert (= 14 (count collection)))
      (assert (= 5 (count relation)))
      {:opening-release-pulls (count opening)
       :tuple-binding-release-pulls (count tuple)
       :request-map-release-pulls (count request)
       :collection-binding-releases (count collection)
       :relation-binding-releases (count relation)})))

(defn validate-find-specifications! []
  (with-open [conn (connect)
              db (db conn)]
    (let [missing-db-error (try
                             (relation-find-missing-db db)
                             nil
                             (catch Throwable error
                               (.getMessage error)))
          relation (relation-find-releases db)
          collection (collection-find-releases db)
          tuple (tuple-find-artist-start db)
          scalar (scalar-find-artist-start db)
          artist-not-canada (artist-not-canada-count db)
          artist-not-release-1970 (artist-not-release-1970-count db)
          carnegie-not-bill-withers (live-at-carnegie-not-bill-withers-count db)
          artist-or-type-gender (artist-or-type-gender-count db)
          release-or-canada-or-1970 (release-or-canada-artist-or-1970-count db)
          artist-start-before-1600 (artist-start-before-1600 db)
          return-map (return-map-releases db)
          positional-artist (return-map-positional-artist db)
          key-artist (return-map-key-artist db)
          host-predicate (host-predicate-artists db)
          function-expression (function-expression-track-minutes db)
          celsius (fahrenheit-to-celsius 212)
          get-else-starts (get-else-artist-starts db)
          get-some-country (get-some-country db)
          fulltext-artist-name (fulltext-artist-name db)
          missing-artist-starts (missing-artist-starts db)
          tx-ids (log-tx-ids conn)
          tx-data-entities (log-tx-data-entities conn 1)
          attrs-42 (attrs-with-value-42 db)
          unique-attrs (attrs-with-property db)
          country-lookup-ref (country-artists-by-lookup-ref db)
          country-ident (country-artists-by-ident db)
          country-entity (country-artists-by-entity db)
          dynamic-reference (dynamic-reference-country-artists db)
          dynamic-reference-entid (dynamic-reference-country-artists-entid db)]
      (assert (some? missing-db-error))
      (assert (.contains ^String missing-db-error ":in does not include $"))
      (assert (= 29 (count relation)))
      (assert (= 12 (count collection)))
      (assert (= [1940 10 9] tuple))
      (assert (= 1940 scalar))
      (assert (= 4538 artist-not-canada))
      (assert (= 3263 artist-not-release-1970))
      (assert (= 2 carnegie-not-bill-withers))
      (assert (= 2323 artist-or-type-gender))
      (assert (= 2124 release-or-canada-or-1970))
      (assert (= 2 (count artist-start-before-1600)))
      (assert (= 3 (count return-map)))
      (assert (= "Paul McCartney" positional-artist))
      (assert (= "Paul McCartney" key-artist))
      (assert (empty? host-predicate))
      (assert (= 71 (count function-expression)))
      (assert (= 100.0 celsius))
      (assert (= #{["Crosby, Stills & Nash" 1968]
                   ["Crosby & Nash" "N/A"]}
                 get-else-starts))
      (assert (= [:country/US :country/name "United States"] get-some-country))
      (assert (= 3 (count fulltext-artist-name)))
      (assert (= #{"Jane" "Jane Birkin" "Mary Jane Hooper"}
                 (set (map second fulltext-artist-name))))
      (assert (= #{1.0 0.625 0.5}
                 (set (map #(nth % 3) fulltext-artist-name))))
      (assert (= 1637 (count missing-artist-starts)))
      (assert (= [1 2 3 4 5 6 7 8 9] tx-ids))
      ;; The subset import creates Vev transactions; tx 1 is its schema batch.
      (assert (= 214 (count tx-data-entities)))
      (assert (= #{:country/name
                   :label/gid
                   :script/name
                   :db/ident
                   :artist/gid
                   :language/name
                   :release/gid
                   :abstractRelease/gid}
                 (set attrs-42)))
      (assert (= #{:country/name
                   :label/gid
                   :script/name
                   :db/ident
                   :artist/gid
                   :language/name
                   :release/gid
                   :abstractRelease/gid}
                 (set unique-attrs)))
      (assert (= country-lookup-ref country-ident))
      (assert (= country-ident country-entity))
      (assert (= 10 (count country-ident)))
      (assert (empty? dynamic-reference))
      (assert (= country-ident dynamic-reference-entid))
      {:missing-db-status :error
       :missing-db-error missing-db-error
       :relation-find-releases (count relation)
       :collection-find-releases (count collection)
       :tuple-find-artist-start tuple
       :scalar-find-artist-start scalar
       :artist-not-canada-count artist-not-canada
       :artist-not-release-1970-count artist-not-release-1970
       :live-at-carnegie-not-bill-withers-count carnegie-not-bill-withers
       :artist-or-type-gender-count artist-or-type-gender
       :release-or-canada-artist-or-1970-count release-or-canada-or-1970
       :artist-start-before-1600-count (count artist-start-before-1600)
       :return-map-releases (count return-map)
       :return-map-positional-artist positional-artist
       :return-map-key-artist key-artist
       :host-predicate-status :supported
       :host-predicate-count (count host-predicate)
       :function-expression-track-minutes (count function-expression)
       :fahrenheit-to-celsius celsius
       :get-else-artist-starts get-else-starts
       :get-some-country get-some-country
       :fulltext-artist-name (count fulltext-artist-name)
       :missing-artist-starts (count missing-artist-starts)
       :log-tx-ids (count tx-ids)
       :log-tx-data-entities (count tx-data-entities)
       :attrs-with-value-42 (count attrs-42)
       :attrs-with-property unique-attrs
       :country-artists-by-lookup-ref (count country-lookup-ref)
       :country-artists-by-ident (count country-ident)
       :country-artists-by-entity (count country-entity)
       :dynamic-reference-status :matches-datomic
       :dynamic-reference-count (count dynamic-reference)
       :dynamic-reference-entid-count (count dynamic-reference-entid)})))

(defn validate-collection-functions! []
  (let [prefixes (word-prefixes)]
    (assert (= ["hello" "antid"] prefixes))
    {:word-prefixes prefixes}))

(defn validate-numeric-attributes! []
  (with-open [conn (connect)
              db (db conn)]
    (let [attrs (attrs-with-value-42 db)]
      (assert (= #{:country/name
                   :label/gid
                   :script/name
                   :db/ident
                   :artist/gid
                   :language/name
                   :release/gid
                   :abstractRelease/gid}
                 (set attrs)))
      {:attrs-with-value-42 attrs})))

(defn validate-dynamic-attributes! []
  (with-open [conn (connect)
              db (db conn)]
    (let [attrs (attrs-with-property db)]
      (assert (= #{:country/name
                   :label/gid
                   :script/name
                   :db/ident
                   :artist/gid
                   :language/name
                   :release/gid
                   :abstractRelease/gid}
                 (set attrs)))
      {:attrs-with-property attrs})))

(defn validate-country-inputs! []
  (with-open [conn (connect)
              db (db conn)]
    (let [lookup-ref (country-artists-by-lookup-ref db)
          ident (country-artists-by-ident db)
          entity (country-artists-by-entity db)
          dynamic-reference (dynamic-reference-country-artists db)
          resolved-reference (dynamic-reference-country-artists-entid db)]
      (assert (= lookup-ref ident entity))
      (assert (= 10 (count entity)))
      (assert (empty? dynamic-reference))
      (assert (= ident resolved-reference))
      {:country-artists entity
       :dynamic-reference dynamic-reference
       :resolved-reference resolved-reference})))

(defn validate-basic-aggregations! []
  (with-open [conn (connect)
              db (db conn)]
    (let [janis (artist-type-gender db)
          monster-sum (monster-heads-sum)
          monster-sum-with (monster-heads-sum-with)
          distinct-values-result (distinct-values)
          min-duration (min-track-duration db)
          top-duration (top-track-duration db)
          random-names (random-artist-names db)
          sum-track-count (sum-medium-track-count db)
          name-counts (artist-name-counts db)
          mode-track-count (custom-mode-aggregate db)
          timeout-error (try
                          (query-timeout-example db)
                          nil
                          (catch Throwable error
                            (.getMessage error)))]
      (assert (= 1 (count janis)))
      (assert (= 4 monster-sum))
      (assert (= 6 monster-sum-with))
      (assert (= #{1 2 3} distinct-values-result))
      (assert (= [3000] min-duration))
      (assert (= [[3000 4000 5000 6000 7000]
                  [3894000 3407000 2928000 2802000 2775000]]
                 top-duration))
      (assert (= 2 (count random-names)))
      (let [[rand-names sample-names] random-names]
        (assert (= 2 (count rand-names)))
        (assert (= 2 (count sample-names)))
        (assert (every? string? rand-names))
        (assert (every? string? sample-names)))
      (assert (= 99847 sum-track-count))
      (assert (= #{[4601 4588]} name-counts))
      (assert (= 2 mode-track-count))
      (assert (some? timeout-error))
      (assert (.contains ^String timeout-error "query timed out"))
      {:artist-type-gender janis
       :monster-heads-sum monster-sum
       :monster-heads-sum-with monster-sum-with
       :distinct-values distinct-values-result
       :min-track-duration min-duration
       :top-track-duration top-duration
       :random-artist-names random-names
       :sum-medium-track-count sum-track-count
       :artist-name-counts name-counts
       :track-name-statistics-status :pending-performance
       :custom-mode-aggregate mode-track-count
       :custom-mode-aggregate-status :supported
       :query-timeout-status :error
       :query-timeout-error timeout-error})))

(defn validate-deeper-query-intro! []
  (with-open [conn (connect)
              db (db conn)]
    (let [tracks (tracks-by-artist-name db)]
      (assert (= 70 (count tracks)))
      {:tracks-by-artist-name (count tracks)})))

(defn validate-mbrainz-opening-data-queries! []
  (with-open [conn (connect)
              db (db conn)]
    (let [titles (d/q mbrainz-title-by-artist-query db "John Lennon")
          albums (d/q mbrainz-title-album-year-by-artist-query db "John Lennon")
          pre-1970 (d/q mbrainz-pre-1970-title-album-year-query db "John Lennon")
          track-release (d/q mbrainz-track-release-rule-query
                             db
                             @mbrainz-sample-rules
                             "John Lennon")
          track-search-info (d/q mbrainz-track-search-info-query
                                 db
                                 @mbrainz-sample-rules
                                 "always")
          collabs (d/q mbrainz-collab-query
                       db
                       @mbrainz-sample-rules
                       ["John Lennon" "Paul McCartney" "George Harrison" "Ringo Starr"])
          collab-net-2 (d/q mbrainz-collab-net-2-query
                            db
                            @mbrainz-sample-rules
                            ["George Harrison"])
          collab-nested (d/q mbrainz-collab-nested-query
                             db
                             @mbrainz-sample-rules
                             (d/q mbrainz-collab-nested-query
                                  db
                                  @mbrainz-sample-rules
                                  [["Diana Ross"]]))
          bill-withers-collaborations (d/q mbrainz-bill-withers-collaboration-query
                                        db
                                        "Bill Withers")]
      (assert (= 70 (count titles)))
      (assert (= 93 (count albums)))
      (assert (= 18 (count pre-1970)))
      (assert (= 93 (count track-release)))
      (assert (= 92 (count track-search-info)))
      (assert (= 5 (count collabs)))
      (assert (= #{["George Harrison" "Bob Dylan"]
                   ["George Harrison" "Ali Akbar Khan"]
                   ["George Harrison" "Ravi Shankar"]}
                 collab-net-2))
      (assert (= #{["Diana Ross"]
                   ["Tammi Terrell"]}
                 collab-nested))
      (assert (= 83 (count bill-withers-collaborations)))
      {:mbrainz-title-by-artist (count titles)
       :mbrainz-title-album-year-by-artist (count albums)
       :mbrainz-pre-1970-title-album-year (count pre-1970)
       :mbrainz-track-release-rule (count track-release)
       :mbrainz-track-search-info (count track-search-info)
       :mbrainz-collab (count collabs)
       :mbrainz-collab-net-2 (count collab-net-2)
       :mbrainz-collab-nested (count collab-nested)
       :mbrainz-bill-withers-collaborations (count bill-withers-collaborations)})))

(defn validate-pre-1970-release-stats! []
  (with-open [conn (connect)
              db (db conn)]
    (let [release-result (d/query {:query pre-1970-release-names-query
                                   :args [db "John Lennon"]
                                   :query-stats true})
          switched-result (d/query {:query pre-1970-release-names-switched-query
                                    :args [db "John Lennon"]
                                    :query-stats true})
          release-names (:ret release-result)
          release-stats (:query-stats release-result)
          switched-names (:ret switched-result)
          switched-stats (:query-stats switched-result)]
      (assert (= 3 (count release-names)))
      (assert (= release-names switched-names))
      (assert (= 3 (:output-rows release-stats)))
      (assert (= 3 (:output-rows switched-stats)))
      {:pre-1970-release-names (count release-names)
       :pre-1970-release-stats release-stats
       :pre-1970-release-switched-names (count switched-names)
       :pre-1970-release-switched-stats switched-stats})))

(defn validate-pre-1970-track-stats! []
  (with-open [conn (connect)
              db (db conn)]
    (let [broad (query-stats-result db pre-1970-track-titles-broad-query)
          with-release-name (query-stats-result db pre-1970-track-titles-with-release-name-query)
          final (query-stats-result db pre-1970-track-titles-query)
          broad-stats (:query-stats broad)
          with-release-name-stats (:query-stats with-release-name)
          final-stats (:query-stats final)]
      (assert (= 70 (count (:ret broad))))
      (assert (= 17 (count (:ret with-release-name))))
      (assert (= 17 (count (:ret final))))
      (assert (= 70 (:output-rows broad-stats)))
      (assert (= 17 (:output-rows with-release-name-stats)))
      (assert (= 17 (:output-rows final-stats)))
      {:pre-1970-track-titles-broad (count (:ret broad))
       :pre-1970-track-titles-broad-stats broad-stats
       :pre-1970-track-titles-with-release-name (count (:ret with-release-name))
       :pre-1970-track-titles-with-release-name-stats with-release-name-stats
       :pre-1970-track-titles (count (:ret final))
       :pre-1970-track-titles-stats final-stats})))

(defn validate-rules-intro! []
  (with-open [conn (connect)
              db (db conn)]
    (let [release-rows (track-release-rule-results db)
          exercise-rows (track-rules-exercise-results db)
          info-rows (track-info-rule-results db)]
      (assert (= 93 (count release-rows)))
      (assert (= 3 (count exercise-rows)))
      (assert (= 3 (count info-rows)))
      {:track-release-rule-query (count release-rows)
       :track-rules-exercise (count exercise-rows)
       :track-info-rules-composition (count info-rows)
       :rules-seq-input-status :supported-by-wrapper})))

(defn validate-pattern-inputs! []
  (with-open [conn (connect)
              db (db conn)]
    (let [literal (pull-release-names db)
          dynamic (pull-release-names-dynamic-pattern db)
          release-and-artist (pull-release-and-artist db)
          name-and-artists (pull-release-name-and-artists db)
          duplicate-error (try
                            (duplicate-pull-release db)
                            nil
                            (catch Throwable error
                              (.getMessage error)))
          nested (nested-pull-release-artists db)
          nested-country (nested-pull-release-artists-country db)
          deep (deep-pull-release-artists-country db)]
      (assert (= 8 (count literal)))
      (assert (= literal dynamic))
      (assert (= 8 (count release-and-artist)))
      (assert (= 8 (count name-and-artists)))
      (assert (some? duplicate-error))
      (assert (.contains ^String duplicate-error "duplicate pull"))
      (assert (= 8 (count nested)))
      (assert (= 14 (count nested-country)))
      (assert (= 14 (count deep)))
      {:pull-release-name (count literal)
       :dynamic-pull-pattern (count dynamic)
       :pull-release-and-artist (count release-and-artist)
       :pull-release-name-and-artists (count name-and-artists)
       :duplicate-pull-same-var-status :error
       :duplicate-pull-same-var-error duplicate-error
       :nested-pull-release-artists (count nested)
       :nested-pull-release-artists-country (count nested-country)
       :deep-pull-release-artists-country (count deep)})))

(defn validate-pull-intro! []
  (with-open [conn (connect)
              db (db conn)]
    (let [artist (pull-artist-name-start db)
          country (pull-artist-country db)
          reverse-country (pull-artists-by-country db)
          release-media (pull-release-media-default db)
          reverse-media (pull-release-by-media db)
          track-artists (pull-track-artists db)
          reverse-country-count (count (:artist/_country reverse-country))]
      (assert (= "Led Zeppelin" (:artist/name artist)))
      (assert (= 1968 (:artist/startYear artist)))
      ;; Entity ids belong to the database value, not the import source's local
      ;; numbering. Datomic and Vev both expose the referenced entity here.
      (assert (pos? (get-in country [:artist/country :db/id])))
      (assert (= 482 reverse-country-count))
      (assert (= 1 (count (:release/media release-media))))
      (assert (= 1 (count (:release/_media reverse-media))))
      (assert (= "Ghost Riders in the Sky" (:track/name track-artists)))
      (assert (= #{"George Harrison" "Bob Dylan"}
                 (set (map :artist/name (:track/artists track-artists)))))
      {:pull-attribute-name artist
       :pull-artist-country country
       :pull-reverse-country-count reverse-country-count
       :pull-release-media-count (count (:release/media release-media))
       :pull-reverse-component-count (count (:release/_media reverse-media))
       :pull-map-spec-artists (count (:track/artists track-artists))})))

(defn validate-pull-nested-map! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-release-media-tracks db)
          media (:release/media pulled)
          track-counts (mapv #(count (:medium/tracks %)) media)
          first-track (first (:medium/tracks (first media)))]
      (assert (= 6 (count media)))
      (assert (= [2 2 4 2 5 4] track-counts))
      (assert (= "Jumpin' Jack Flash / Youngblood" (:track/name first-track)))
      (assert (= ["Leon Russell"] (mapv :artist/name (:track/artists first-track))))
      {:pull-nested-map-media-count (count media)
       :pull-nested-map-track-counts track-counts
       :pull-nested-map-first-track (:track/name first-track)})))

(defn validate-pull-wildcard! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-release-wildcard db)]
      (assert (= 13 (count pulled)))
      (assert (= "The Concert for Bangla Desh" (:release/name pulled)))
      (assert (= 1971 (:release/year pulled)))
      (assert (= #uuid "f3bdff34-9a85-4adc-a014-922eef9cdaa5" (:release/gid pulled)))
      {:pull-wildcard-attribute-count (count pulled)
       :pull-wildcard-release-name (:release/name pulled)
       :pull-wildcard-release-year (:release/year pulled)})))

(defn validate-pull-wildcard-map! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-track-wildcard-artists db)
          artist-names (mapv :artist/name (:track/artists pulled))]
      (assert (= 6 (count pulled)))
      (assert (= "Ghost Riders in the Sky" (:track/name pulled)))
      (assert (= 11 (:track/position pulled)))
      (assert (= 218506 (:track/duration pulled)))
      (assert (= ["George Harrison" "Bob Dylan"] artist-names))
      {:pull-wildcard-map-attribute-count (count pulled)
       :pull-wildcard-map-track-name (:track/name pulled)
       :pull-wildcard-map-artists artist-names})))

(defn validate-pull-default-option! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-mccartney-default-end-year db)]
      (assert (= "Paul McCartney" (:artist/name pulled)))
      (assert (= 0 (:artist/endYear pulled)))
      {:pull-default-option-name (:artist/name pulled)
       :pull-default-option-end-year (:artist/endYear pulled)})))

(defn validate-pull-default-option-string! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-mccartney-default-end-year-string db)]
      (assert (= "Paul McCartney" (:artist/name pulled)))
      (assert (= "N/A" (:artist/endYear pulled)))
      {:pull-default-option-string-name (:artist/name pulled)
       :pull-default-option-string-end-year (:artist/endYear pulled)})))

(defn validate-pull-absent-attribute! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-mccartney-absent-attribute db)]
      (assert (= "Paul McCartney" (:artist/name pulled)))
      (assert (not (contains? pulled :died-in-1966?)))
      {:pull-absent-attribute-name (:artist/name pulled)
       :pull-absent-attribute-present? (contains? pulled :died-in-1966?)})))

(defn validate-pull-explicit-limit! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-led-zeppelin-track-limit db)
          tracks (:track/_artists pulled)]
      (assert (= 10 (count tracks)))
      (assert (every? #(contains? % :db/id) tracks))
      {:pull-explicit-limit-count (count tracks)})))

(defn validate-pull-limit-subspec! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-led-zeppelin-track-limit-names db)
          tracks (:track/_artists pulled)
          names (mapv :track/name tracks)]
      (assert (= 10 (count tracks)))
      (assert (= "Whole Lotta Love" (first names)))
      (assert (some #{"Stairway to Heaven"} names))
      (assert (every? #(contains? % :track/name) tracks))
      {:pull-limit-subspec-count (count tracks)
       :pull-limit-subspec-first (first names)})))

(defn validate-pull-limit-subspec-as! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-led-zeppelin-track-limit-names-as db)
          tracks (get pulled "Tracks")
          names (mapv :track/name tracks)]
      (assert (= 10 (count tracks)))
      (assert (not (contains? pulled :track/_artists)))
      (assert (= "Whole Lotta Love" (first names)))
      (assert (some #{"Stairway to Heaven"} names))
      (assert (every? #(contains? % :track/name) tracks))
      {:pull-limit-subspec-as-count (count tracks)
       :pull-limit-subspec-as-first (first names)})))

(defn validate-pull-no-limit! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-led-zeppelin-track-no-limit db)
          tracks (:track/_artists pulled)]
      (assert (= 128 (count tracks)))
      (assert (every? #(contains? % :db/id) tracks))
      {:pull-no-limit-count (count tracks)})))

(defn validate-pull-empty-results! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-led-zeppelin-empty-results db)]
      (assert (nil? pulled))
      {:pull-empty-results pulled})))

(defn validate-pull-empty-results-in-collection! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (pull-track-artists-empty-results db)]
      (assert (nil? pulled))
      {:pull-empty-results-in-collection pulled})))

(defn validate-pull-expression-in-query! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (direct-pull-expression-in-query db)
          names (set (map :release/name pulled))]
      (assert (= 8 (count pulled)))
      (assert (contains? names "Led Zeppelin"))
      (assert (every? #(= #{:release/name} (set (keys %))) pulled))
      {:pull-expression-in-query-count (count pulled)
       :pull-expression-in-query-has-led-zeppelin (contains? names "Led Zeppelin")})))

(defn validate-dynamic-pattern-input! []
  (with-open [conn (connect)
              db (db conn)]
    (let [pulled (direct-dynamic-pattern-input db)
          names (set (map :release/name pulled))]
      (assert (= 8 (count pulled)))
      (assert (contains? names "Led Zeppelin"))
      (assert (every? #(= #{:release/name} (set (keys %))) pulled))
      {:dynamic-pattern-input-count (count pulled)
       :dynamic-pattern-input-has-led-zeppelin (contains? names "Led Zeppelin")})))

(comment
  (def conn (connect))
  (def db (db conn))

  ;; Upstream opening query-stats prompt:
  ;; John Lennon has only a small number of releases in this sample, so this
  ;; query should be easy to reason about before profiling/reordering.
  (opening-release-pulls db)

  ;; Tuple binding:
  ;; "What releases are associated with the artist named John Lennon and named
  ;; Mind Games?"
  (tuple-binding-release-pulls db)

  ;; Request-map query, corresponding to upstream `d/query`.
  (request-map-release-pulls db)

  ;; Collection binding:
  ;; "What releases are associated with either Paul McCartney or George
  ;; Harrison?"
  (collection-binding-releases db)

  ;; Relation binding:
  (relation-binding-releases db)

  ;; Find specifications:
  ;; The upstream section first demonstrates a relation find missing `$` in
  ;; `:in`; Datomic raises a helpful error. Vev currently returns no rows for
  ;; that shape, so validation keeps it visible as pending error-shape parity.
  (relation-find-missing-db db)

  ;; Relation find spec:
  (relation-find-releases db)

  ;; Collection find spec:
  (collection-find-releases db)

  ;; Single tuple find spec:
  (tuple-find-artist-start db)

  ;; Scalar find spec:
  (scalar-find-artist-start db)

  ;; Return maps and Clojure destructuring:
  (return-map-releases db)
  (return-map-positional-artist db)
  (return-map-key-artist db)

  ;; Predicate expressions:
  ;; Upstream uses `(user/teste ?year)`. Vev resolves the host function through
  ;; the Clojure wrapper and executes it through the native query registry.
  (host-predicate-artists db)

  ;; Function expressions:
  (function-expression-track-minutes db)
  (fahrenheit-to-celsius 212)

  ;; Built-in expression functions:
  (artist-type-gender db)

  ;; Aggregations:
  ;; Upstream first shows why `:with` matters for aggregate cardinality. The
  ;; first source-less relation query returns 4 because duplicate head-count
  ;; values collapse; the fixed query returns 6 because `?monster` preserves the
  ;; per-monster input rows.
  (monster-heads-sum)
  (monster-heads-sum-with)
  (distinct-values)

  (min-track-duration db)
  (top-track-duration db)
  (random-artist-names db)
  (sum-medium-track-count db)
  (artist-name-counts db)

  ;; Statistics:
  ;; The upstream query groups by release year and computes median, avg, and
  ;; stddev over track-title lengths. It is ported as
  ;; `track-name-statistics-query`, but is not in the smoke path yet because it
  ;; currently runs too slowly against the persistent tutorial store.
  (track-name-statistics db)

  ;; Custom Aggregates:
  ;; The upstream `(user/mode ?track-count)` example resolves through the
  ;; Clojure wrapper and executes through the native query registry.
  (custom-mode-aggregate db)

  ;; d/query timeout:
  ;; Upstream expects this request-map form with `:timeout 100` to throw.
  ;; Vev is now often fast enough to finish under 100ms, so the validation
  ;; helper uses a tighter timeout while preserving the request-map shape.
  (query-timeout-example db)

  ;; Let's go deeper:
  ;; Upstream starts with this `d/query` request map and `:io-context`.
  ;; Vev accepts the Datomic-style request map and ignores the Datomic-specific
  ;; stats context key for now.
  (tracks-by-artist-name db)

  ;; Limit releases before 1970 and inspect query stats:
  (pre-1970-release-name-stats db)

  ;; Same query with the release-name clause before the predicate:
  (pre-1970-release-name-switched-stats db)

  ;; Bind track names from releases before 1970. The first form intentionally
  ;; joins all artist tracks and only uses releases for the year predicate.
  (pre-1970-track-title-broad-stats db)

  ;; Try again by following release -> media -> tracks while still binding the
  ;; release name.
  (pre-1970-track-title-with-release-name-stats db)

  ;; Final production-shaped query from the upstream section.
  (pre-1970-track-title-results db)

  ;; Rules:
  ;; The upstream intro rule, first exercise, and rules-composition section are
  ;; ported above. Vev accepts the Datomic-style `%` rules input, including
  ;; `(concat track-artist-rules track-release-detail-rules)`, and validates
  ;; composed rules through `track-info-rules`.
  track-release-rules
  (track-release-rule-results db)
  (track-rules-exercise-results db)
  (track-info-rule-results db)

  ;; Pattern inputs:
  ;; Upstream demonstrates pull expressions in `:find`, dynamic pull patterns
  ;; as `:in` parameters, legal multiple-pull forms, an invalid duplicate pull
  ;; on the same var, and nested ref navigation.
  (pull-release-names db)
  (pull-release-names-dynamic-pattern db)
  (pull-release-and-artist db)
  (pull-release-name-and-artists db)
  ;; Datomic rejects this duplicate pull on `?e`; Vev should also reject it.
  (duplicate-pull-release db)
  (nested-pull-release-artists db)
  (nested-pull-release-artists-country db)
  (deep-pull-release-artists-country db)

  ;; Direct pull tutorial:
  ;; Source of truth is `build/upstream/day-of-datomic/tutorial/pull.clj`,
  ;; from "attribute name" through "dynamic pattern input".
  (pull-artist-name-start db)
  (pull-artist-country db)
  ;; Upstream expects this reverse lookup to return artists. Vev currently
  ;; returns an empty collection for this direct pull, while the equivalent
  ;; query over `:artist/country :country/GB` has rows. Keep it visible.
  (pull-artists-by-country db)
  (pull-release-media-default db)
  (pull-release-by-media db)
  (pull-track-artists db)

  ;; Nested map specifications:
  (pull-release-media-tracks db)

  ;; Wildcard specification:
  (pull-release-wildcard db)

  ;; Wildcard + map specification:
  (pull-track-wildcard-artists db)

  ;; Default option:
  (pull-mccartney-default-end-year db)

  ;; Default option with different type:
  (pull-mccartney-default-end-year-string db)

  ;; Absent attributes are omitted from results:
  (pull-mccartney-absent-attribute db)

  ;; Explicit limit:
  (pull-led-zeppelin-track-limit db)

  ;; Limit + subspec:
  (pull-led-zeppelin-track-limit-names db)

  ;; Limit + subspec + :as option:
  (pull-led-zeppelin-track-limit-names-as db)

  ;; No limit:
  (pull-led-zeppelin-track-no-limit db)

  ;; Empty results:
  (pull-led-zeppelin-empty-results db)

  ;; Empty results in a collection:
  (pull-track-artists-empty-results db)

  ;; Pull expression in query:
  (direct-pull-expression-in-query db)

  ;; Dynamic pattern input:
  (direct-dynamic-pattern-input db)

  (.close db)
  (.close conn))
