(ns vev-datascript-bench.datalevin-runner
  (:require [datalevin.core :as d]
            [datalevin-bench.datalevin :as benchmark]))

(def benchmark-dbs
  '[db100k-1 db100k-2 db100k-2s db100k-3 db100k-4 db100k-5
    db100k-p1 db100k-p2])

(defn close-benchmark-dbs! []
  (doseq [db-name benchmark-dbs]
    (when-some [db-var (ns-resolve 'datalevin-bench.datalevin db-name)]
      (try
        (d/close-db @db-var)
        (catch Throwable _)))))

(defn -main [& names]
  (try
    (apply benchmark/-main names)
    (finally
      ;; Upstream constructs all benchmark databases eagerly but only closes
      ;; databases selected on the command line. Close the unselected ones too
      ;; so Datalevin can stop its process-wide executors.
      (close-benchmark-dbs!)
      (shutdown-agents))))
