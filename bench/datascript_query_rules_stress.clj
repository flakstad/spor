(require '[datascript.core :as d])

(def schema
  {:follows {:db/valueType :db.type/ref
             :db/cardinality :db.cardinality/many}
   :f1 {:db/valueType :db.type/ref
        :db/cardinality :db.cardinality/many}
   :f2 {:db/valueType :db.type/ref
        :db/cardinality :db.cardinality/many}})

(def rules
  '[[(reachable ?x ?y)
     [?x :follows ?y]]
    [(reachable ?x ?y)
     [?x :follows ?t]
     (reachable ?t ?y)]])

(defn elapsed-us [start]
  (/ (double (- (System/nanoTime) start)) 1000.0))

(defn median [xs]
  (nth (sort xs) (quot (count xs) 2)))

(defn percentile [sorted-xs numerator denominator]
  (let [last-index (dec (count sorted-xs))
        index (min last-index (quot (* (count sorted-xs) numerator) denominator))]
    (nth sorted-xs index)))

(defn seed-chain [n]
  (vec
    (concat
      (mapcat
        (fn [i]
          [{:db/id i :name (str "node-" i)}
           {:db/id i :follows (inc i)}])
        (range 1 n))
      [{:db/id n :name (str "node-" n)}])))

(defn seed-tree [n width]
  (vec
    (mapcat
      (fn [i]
        (let [children (filter #(<= % n)
                               (map #(+ (* (dec i) width) % 1)
                                    (range 1 (inc width))))]
          (if (seq children)
            [{:db/id i :name (str "node-" i) :follows (vec children)}]
            [{:db/id i :name (str "node-" i)}])))
      (range 1 (inc n)))))

(defn seed-dense-dag [n width]
  (vec
    (map
      (fn [i]
        (let [targets (vec
                        (filter #(<= % n)
                                (map #(+ i %) (range 1 (inc width)))))]
          (cond-> {:db/id i
                   :name (str "node-" i)
                   :active true}
            (seq targets) (assoc :follows targets))))
      (range 1 (inc n)))))

(defn seed-mutual-chain [n]
  (vec
    (concat
      (mapcat
        (fn [i]
          [{:db/id i :name (str "node-" i)}
           {:db/id i :f1 (inc i)}
           {:db/id i :f2 (inc i)}])
        (range 1 n))
      [{:db/id n :name (str "node-" n)}])))

(defn db-with [tx]
  (d/db-with (d/empty-db schema) tx))

(defn time-query [f warmups samples-count]
  (dotimes [_ warmups]
    (count (f)))
  (let [samples
        (doall
          (for [_ (range samples-count)]
            (let [start (System/nanoTime)
                  result (f)
                  rows (count result)]
              {:elapsed-us (elapsed-us start)
               :rows rows})))
        sorted-times (sort (map :elapsed-us samples))]
    {:min-us (first sorted-times)
     :median-us (median sorted-times)
     :p90-us (percentile sorted-times 9 10)
     :max-us (last sorted-times)
     :rows (:rows (first samples))}))

(defn print-result [workload n measured]
  (println
    (format
      "engine=datascript workload=%s n=%d ok=true rows=%d min_us=%.0f median_us=%.0f p90_us=%.0f max_us=%.0f steps= clauses= candidates= rule_calls= rule_iterations= max_bindings="
      workload
      n
      (:rows measured)
      (:min-us measured)
      (:median-us measured)
      (:p90-us measured)
      (:max-us measured))))

(defn run-chain-from-root [n]
  (let [db (db-with (seed-chain n))
        measured (time-query (fn []
                             (d/q '[:find ?y :in $ % ?x :where (reachable ?x ?y)]
                                    db rules 1))
                             3
                             5)]
    (print-result "stress-chain-root" n measured)))

(defn run-chain-to-leaf [n]
  (let [db (db-with (seed-chain n))
        measured (time-query (fn []
                             (d/q '[:find ?x :in $ % ?y :where (reachable ?x ?y)]
                                    db rules n))
                             3
                             5)]
    (print-result "stress-chain-leaf" n measured)))

(defn run-chain-all [n]
  (let [db (db-with (seed-chain n))
        measured (time-query (fn []
                             (d/q '[:find ?x ?y :in $ % :where (reachable ?x ?y)]
                                    db rules))
                             2
                             3)]
    (print-result "stress-chain-all" n measured)))

(defn run-tree-from-root [n]
  (let [db (db-with (seed-tree n 3))
        measured (time-query (fn []
                             (d/q '[:find ?y :in $ % ?x :where (reachable ?x ?y)]
                                    db rules 1))
                             3
                             5)]
    (print-result "stress-tree-root" n measured)))

(defn run-dense-from-root [n]
  (let [db (db-with (seed-dense-dag n 8))
        measured (time-query (fn []
                             (d/q '[:find ?y :in $ % ?x :where (reachable ?x ?y)]
                                    db rules 1))
                             3
                             5)]
    (print-result "stress-dense-root" n measured)))

(def filtered-rules
  '[[(filtered-reachable ?x ?y)
     [?x :follows ?y]
     [?y :active true]]
    [(filtered-reachable ?x ?y)
     [?x :follows ?t]
     [?t :active true]
     (filtered-reachable ?t ?y)]])

(defn run-filtered-from-root [n]
  (let [db (db-with (seed-dense-dag n 1))
        measured (time-query (fn []
                             (d/q '[:find ?y :in $ % ?x :where (filtered-reachable ?x ?y)]
                                    db filtered-rules 1))
                             1
                             3)]
    (print-result "stress-filtered-root" n measured)))

(def mutual-rules
  '[[(f1 ?x ?y)
     [?x :f1 ?y]]
    [(f1 ?x ?y)
     [?x :f1 ?t]
     (f2 ?t ?y)]
    [(f2 ?x ?y)
     [?x :f2 ?y]]
    [(f2 ?x ?y)
     [?x :f2 ?t]
     (f1 ?t ?y)]])

(defn run-mutual-from-root [n]
  (let [db (db-with (seed-mutual-chain n))
        measured (time-query (fn []
                             (d/q '[:find ?y :in $ % ?x :where (f1 ?x ?y)]
                                    db mutual-rules 1))
                             1
                             3)]
    (print-result "stress-mutual-root" n measured)))

(doseq [n [300]]
  (run-chain-from-root n)
  (run-chain-to-leaf n))
(doseq [n [200]]
  (run-chain-all n))
(doseq [n [364]]
  (run-tree-from-root n))
(doseq [n [30]]
  (run-mutual-from-root n))
