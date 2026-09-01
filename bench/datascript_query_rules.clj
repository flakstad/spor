(require '[datascript.core :as d])

(def schema
  {:follows {:db/valueType :db.type/ref
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

(defn seed-people [n]
  (vec
    (map
      (fn [i]
        {:db/id i
         :email (str "user-" i "@example.com")
         :name (str "User " i)
         :age (mod i 100)})
      (range 1 (inc n)))))

(defn db-with [tx]
  (d/db-with (d/empty-db schema) tx))

(defn time-query [f]
  (dotimes [_ 100]
    (count (f)))
  (let [samples
        (doall
          (for [_ (range 100)]
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
                                    db rules 1)))]
    (print-result "chain-root" n measured)))

(defn run-chain-all [n]
  (let [db (db-with (seed-chain n))
        measured (time-query (fn []
                               (d/q '[:find ?x ?y :in $ % :where (reachable ?x ?y)]
                                    db rules)))]
    (print-result "chain-all" n measured)))

(defn run-chain-to-leaf [n]
  (let [db (db-with (seed-chain n))
        measured (time-query (fn []
                               (d/q '[:find ?x :in $ % ?y :where (reachable ?x ?y)]
                                    db rules n)))]
    (print-result "chain-leaf" n measured)))

(defn run-tree-from-root [n]
  (let [db (db-with (seed-tree n 3))
        measured (time-query (fn []
                               (d/q '[:find ?y :in $ % ?x :where (reachable ?x ?y)]
                                    db rules 1)))]
    (print-result "tree-root" n measured)))

(defn run-bad-order-join [n]
  (let [db (db-with (seed-people n))
        email (str "user-" (quot n 2) "@example.com")
        measured (time-query (fn []
                               (d/q '[:find ?name ?age
                                      :in $ ?email
                                      :where
                                      [?e :age ?age]
                                      [?e :email ?email]
                                      [?e :name ?name]]
                                    db email)))]
    (print-result "bad-order-join" n measured)))

(defn run-distinct-age [n]
  (let [db (db-with (seed-people n))
        measured (time-query (fn []
                               (d/q '[:find ?age
                                      :where
                                      [?e :age ?age]]
                                    db)))]
    (print-result "distinct-age" n measured)))

(defn run-people-name-age [n]
  (let [db (db-with (seed-people n))
        measured (time-query (fn []
                               (d/q '[:find ?name ?age
                                      :where
                                      [?e :name ?name]
                                      [?e :age ?age]]
                                    db)))]
    (print-result "people-name-age" n measured)))

(doseq [n [3 10 30 100]]
  (run-chain-from-root n))
(doseq [n [10 30 100]]
  (run-chain-to-leaf n))
(doseq [n [10 30 100]]
  (run-chain-all n))
(doseq [n [4 13 40 121]]
  (run-tree-from-root n))
(doseq [n [1000]]
  (run-bad-order-join n))
(doseq [n [1000]]
  (run-distinct-age n))
(doseq [n [1000]]
  (run-people-name-age n))
