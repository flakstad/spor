(ns getting-started
  (:require [vev.core :as d]))

(comment
  (def conn (d/create-conn))

  (d/transact conn
               [[:db/add 100 :db/ident :user/friend]
                [:db/add 100 :db/valueType :db.type/ref]
                {:db/id 1
                 :user/name "Ada"
                 :user/email "ada@example.com"}
                {:db/id 2
                 :user/name "Grace"
                 :user/email "grace@example.com"
                 :user/friend 1}])

  (def db (d/db conn))

  (d/q '[:find ?name
         :where [?e :user/name ?name]]
       db)

  (d/pull db
          [:user/name {:user/friend [:user/name]}]
          2)

  (d/q '[:find ?name
         :in $ ?email
         :where [?e :user/email ?email]
                [?e :user/name ?name]]
       db
       "ada@example.com")

  (def listener
    (d/listen conn :audit #(println (:tx-data %))))

  (d/transact conn [{:db/id 3 :user/name "Barbara"}])

  (d/unlisten conn listener)

  (def next-db
    (d/db-with db [{:db/id 4 :user/name "Katherine"}]))

  (d/q '[:find ?name
         :where [?e :user/name ?name]]
       next-db)

  (def durable (d/connect "app.vev"))

  (d/transact durable [{:db/id 1 :user/name "Durable Ada"}])

  (d/q '[:find ?name
         :where [?e :user/name ?name]]
       (d/db durable)))
