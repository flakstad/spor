(ns vev-comparison.deterministic-core
  (:import [java.util ArrayList Collections Random]))

(def names ["Ivan" "Petr" "Sergei" "Oleg" "Yuri" "Dmitry" "Fedor" "Denis"])
(def last-names ["Ivanov" "Petrov" "Sidorov" "Kovalev" "Kuznetsov" "Voronoi"])
(def sexes [:male :female])

(defn env-long [name default]
  (Long/parseLong (or (System/getenv name) (str default))))

(defn env-double [name default]
  (Double/parseDouble (or (System/getenv name) (str default))))

(defn people [person-count]
  (let [rng (Random. 42)
        values
          (mapv
            (fn [id]
              {:db/id (str id)
               :name (nth names (.nextInt rng (clojure.core/count names)))
               :last-name (nth last-names (.nextInt rng (clojure.core/count last-names)))
               :sex (nth sexes (.nextInt rng (clojure.core/count sexes)))
               :age (.nextInt rng 100)
               :salary (.nextInt rng 100000)})
            (range 1 (inc person-count)))
        shuffled (ArrayList. values)]
    (Collections/shuffle shuffled (Random. 43))
    (vec shuffled)))

(defn now-ms []
  (/ (System/nanoTime) 1000000.0))

(defn to-fixed [value places]
  (String/format java.util.Locale/US
                 (str "%." places "f")
                 (object-array [(double value)])))

(defn round-value [value]
  (cond
    (> value 1) (to-fixed value 1)
    (> value 0.001) (to-fixed value 2)
    :else value))

(defn percentile [values quantile]
  (let [ordered (vec (sort values))
        index (min (dec (count ordered))
                   (int (* quantile (count ordered))))]
    (nth ordered index)))
