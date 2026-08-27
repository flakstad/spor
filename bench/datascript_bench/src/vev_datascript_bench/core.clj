;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns vev-datascript-bench.core
  (:require [clojure.string :as str])
  (:import [java.util ArrayList Collections Random]))

(def ^:dynamic *warmup-t*
  (Double/parseDouble (or (System/getenv "VEV_BENCH_WARMUP_MS") "500")))

(def ^:dynamic *bench-t*
  (Double/parseDouble (or (System/getenv "VEV_BENCH_MS") "1000")))

(def ^:dynamic *step*
  (Long/parseLong (or (System/getenv "VEV_BENCH_STEP") "10")))

(def ^:dynamic *repeats*
  (Long/parseLong (or (System/getenv "VEV_BENCH_REPEATS") "5")))

(def ^:dynamic *people-count*
  (Long/parseLong (or (System/getenv "VEV_BENCH_PEOPLE") "20000")))

(def names ["Ivan" "Petr" "Sergei" "Oleg" "Yuri" "Dmitry" "Fedor" "Denis"])
(def last-names ["Ivanov" "Petrov" "Sidorov" "Kovalev" "Kuznetsov" "Voronoi"])
(def sexes [:male :female])

(defn random-man [^java.util.Random rng id]
  {:db/id     id
   :name      (nth names (.nextInt rng (count names)))
   :last-name (nth last-names (.nextInt rng (count last-names)))
   :sex       (nth sexes (.nextInt rng (count sexes)))
   :age       (.nextInt rng 100)
   :salary    (.nextInt rng 100000)})

(defn people
  ([] (people 20000))
  ([n]
   (let [rng (Random. 42)
         values (ArrayList. (mapv #(random-man rng %) (range 1 (inc n))))]
     (Collections/shuffle values (Random. 43))
     (vec values))))

(def people20k (delay (people *people-count*)))

(defn now-ms []
  (/ (System/nanoTime) 1000000.0))

(defn to-fixed [n places]
  (String/format java.util.Locale/US (str "%." places "f") (object-array [(double n)])))

(defn round [n]
  (cond
    (> n 1)     (to-fixed n 1)
    (> n 0.001) (to-fixed n 2)
    :else       n))

(defn percentile [xs n]
  (-> (sort xs)
      (nth (min (dec (count xs))
                (int (* n (count xs)))))))

(defmacro dotime [duration & body]
  `(let [start-t# (now-ms)
         end-t#   (+ ~duration start-t#)]
     (loop [iterations# *step*]
       (dotimes [_# *step*]
         ~@body)
       (let [now# (now-ms)]
         (if (< now# end-t#)
           (recur (+ *step* iterations#))
           (double (/ (- now# start-t#) iterations#)))))))

(defmacro bench [& body]
  `(let [_#       (dotime *warmup-t* ~@body)
         results# (into []
                        (for [_# (range *repeats*)]
                          (dotime *bench-t* ~@body)))]
     (when (= "1" (System/getenv "VEV_BENCH_SAMPLE_LOG"))
       (binding [*out* *err*]
         (println "benchmark_samples"
                  (or (System/getenv "VEV_BENCH_ENGINE") "unknown")
                  (str/join "," results#))))
     (percentile results# 0.5)))
