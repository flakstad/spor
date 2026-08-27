;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns datalevin-bench.core
  (:require [clojure.string :as str]
            [vev-comparison.deterministic-core :as deterministic]))

(def ^:dynamic *warmup-t* (deterministic/env-double "VEV_BENCH_WARMUP_MS" 500))
(def ^:dynamic *bench-t* (deterministic/env-double "VEV_BENCH_MS" 1000))
(def ^:dynamic *step* (deterministic/env-long "VEV_BENCH_STEP" 10))
(def ^:dynamic *repeats* (deterministic/env-long "VEV_BENCH_REPEATS" 5))
(def people20k
  (deterministic/people (deterministic/env-long "VEV_BENCH_PEOPLE" 20000)))

(defn now [] (deterministic/now-ms))
(defn round [value] (deterministic/round-value value))
(defn percentile [values quantile] (deterministic/percentile values quantile))

(defmacro dotime [duration & body]
  `(let [start-t# (now)
         end-t# (+ ~duration start-t#)]
     (loop [iterations# *step*]
       (dotimes [_# *step*] ~@body)
       (let [now# (now)]
         (if (< now# end-t#)
           (recur (+ *step* iterations#))
           (double (/ (- now# start-t#) iterations#)))))))

(defmacro bench [& body]
  `(let [_# (dotime *warmup-t* ~@body)
         results# (into []
                    (for [_# (range *repeats*)]
                      (dotime *bench-t* ~@body)))]
     (when (= "1" (System/getenv "VEV_BENCH_SAMPLE_LOG"))
       (binding [*out* *err*]
         (println "benchmark_samples"
                  (or (System/getenv "VEV_BENCH_ENGINE") "unknown")
                  (str/join "," results#))))
     (percentile results# 0.5)))

(defmacro bench-once [& body]
  `(let [start-t# (now)]
     ~@body
     (- (now) start-t#)))

(defmacro bench-10 [& body]
  `(let [_# (dotime 2 ~@body)
         results# (into []
                    (for [_# (range *repeats*)]
                      (dotime 5 ~@body)))]
     (percentile results# 0.5)))
