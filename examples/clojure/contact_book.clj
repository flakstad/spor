;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns contact-book
  (:require [clojure.java.io :as io]
            [vev.core :as d]))

(def schema
  [[:db/add 10 :db/ident :contact/email]
   [:db/add 10 :db/unique :db.unique/identity]
   [:db/add 11 :db/ident :contact/knows]
   [:db/add 11 :db/valueType :db.type/ref]])

(def contacts
  [{:db/id 1
    :contact/name "Ada Lovelace"
    :contact/email "ada@example.com"
    :contact/company "Analytical Engines"}
   {:db/id 2
    :contact/name "Grace Hopper"
    :contact/email "grace@example.com"
    :contact/company "Compilers"}
   [:db/add 1 :contact/knows 2]])

(def katherine
  [{:db/id 3
    :contact/name "Katherine Johnson"
    :contact/email "katherine@example.com"
    :contact/company "NASA"}])

(def names-query
  '[:find ?name
    :where [?e :contact/name ?name]])

(def email-query
  '[:find ?name
    :in $ ?email
    :where [?e :contact/email ?email]
           [?e :contact/name ?name]])

(def contact-pattern
  [:contact/name :contact/email {:contact/knows [:contact/name]}])

(defn remove-store! [path]
  (doseq [suffix ["" "-wal" "-shm"]]
    (io/delete-file (str path suffix) true)))

(defn seed! [conn]
  (d/transact conn schema)
  (d/transact conn contacts))

(defn contact-names [source]
  (->> (d/q names-query source)
       (map first)
       sort
       vec))

(defn assert-base-contacts! [db]
  (assert (= ["Ada Lovelace" "Grace Hopper"] (contact-names db)))
  (assert (= #{["Ada Lovelace"]}
             (d/q email-query db "ada@example.com")))
  (let [profile (d/pull db contact-pattern 1)]
    (assert (= "Ada Lovelace" (:contact/name profile)))
    (assert (= "Grace Hopper" (get-in profile [:contact/knows :contact/name])))))

(defn run-in-memory! []
  (with-open [conn (d/create-conn)]
    (seed! conn)
    (let [db (d/db conn)
          next-db (d/db-with db katherine)]
      (assert-base-contacts! db)
      (assert (some #{"Katherine Johnson"} (contact-names next-db)))
      (assert (not-any? #{"Katherine Johnson"} (contact-names db))))))

(defn run-durable! [path]
  (remove-store! path)
  (with-open [conn (d/connect path)]
    (seed! conn)
    (let [db (d/db conn)]
      (assert-base-contacts! db)))
  (with-open [conn (d/connect path)]
    (assert (= ["Ada Lovelace" "Grace Hopper"] (contact-names conn)))
    (d/transact conn katherine)
    (assert (some #{"Katherine Johnson"} (contact-names conn))))
  (with-open [conn (d/connect path)]
    (assert (some #{"Katherine Johnson"} (contact-names conn))))
  (remove-store! path))

(defn -main [& [path]]
  (let [store (or path
                  (str (System/getProperty "java.io.tmpdir")
                       "/vev-contact-book-clojure.vev"))]
    (run-in-memory!)
    (run-durable! store)
    (println "contact-book-clojure: ok")))
