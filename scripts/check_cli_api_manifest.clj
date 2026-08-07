;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(require '[clojure.edn :as edn]
         '[clojure.java.io :as io]
         '[clojure.set :as set])

(def public-form-patterns
  {:kvist #"(?m)^\((?:def|defn|defmacro)\s+([^\s\[\)]+)"
   :clojure #"(?m)^\((?:def|defn|defmacro|defmulti|defrecord|deftype)\s+([^\s\[\)]+)"})

(defn public-names [frontend path]
  (->> (re-seq (get public-form-patterns frontend)
               (slurp (io/file path)))
       (map (comp symbol second))
       set))

(defn fail! [message data]
  (throw (ex-info message data)))

(let [[manifest-path kvist-path clojure-path] *command-line-args*
      manifest (edn/read-string (slurp (io/file manifest-path)))
      allowed (:allowed-dispositions manifest)
      expected {:kvist (public-names :kvist kvist-path)
                :clojure (public-names :clojure clojure-path)}]
  (when-not (= 1 (:format-version manifest))
    (fail! "unsupported CLI API manifest format"
           {:format-version (:format-version manifest)}))
  (doseq [[frontend required] expected]
    (let [entries (get-in manifest [:frontends frontend])
          names (map :name entries)
          actual (set names)
          duplicates (->> (frequencies names)
                          (keep (fn [[name n]] (when (> n 1) name)))
                          set)
          missing (set/difference required actual)
          unexpected (set/difference actual required)]
      (when (seq duplicates)
        (fail! "duplicate CLI API manifest entries"
               {:frontend frontend :duplicates duplicates}))
      (when (seq missing)
        (fail! "public APIs missing from CLI API manifest"
               {:frontend frontend :missing missing}))
      (when (seq unexpected)
        (fail! "unknown APIs in CLI API manifest"
               {:frontend frontend :unexpected unexpected}))
      (doseq [entry entries]
        (when-not (contains? allowed (:disposition entry))
          (fail! "invalid CLI API disposition"
                 {:frontend frontend :entry entry})))))
  (println (pr-str {:status :ok
                    :kvist (count (:kvist expected))
                    :clojure (count (:clojure expected))})))
