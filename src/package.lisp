;;;; package.lisp --- Package definition for the USER-AGENTS system.

(defpackage #:user-agents
  (:nicknames #:ua)
  (:use #:cl)
  (:export
   ;; Version and provenance of the vendored upstream dataset.
   #:*version*
   #:*upstream-version*
   #:*data-sha256*
   #:*data-retrieved*
   #:*data-record-count*
   #:*data-source-url*
   #:version

   ;; Conditions.
   #:user-agents-error
   #:no-matching-user-agents
   #:no-matching-user-agents-filter

   ;; The raw dataset.
   #:*data-file*
   #:all-user-agents
   #:user-agent-count
   #:reload-data

   ;; Filters.
   #:regex
   #:regex-p
   #:all-of
   #:any-of
   #:none-of
   #:compile-filter
   #:filter-matches-p

   ;; Pools (a filtered, weight-normalized slice of the dataset).
   #:pool
   #:poolp
   #:make-pool
   #:pool-size
   #:pool-filter
   #:pool-entries

   ;; User agents.
   #:user-agent
   #:user-agent-p
   #:make-user-agent
   #:random-user-agent
   #:randomize
   #:next-user-agent
   #:user-agent-pool
   #:user-agent-data
   #:user-agent-string
   #:top

   ;; Field access.
   #:field
   #:app-name
   #:connection
   #:device-category
   #:language
   #:oscpu
   #:platform
   #:plugins-length
   #:screen-height
   #:screen-width
   #:vendor
   #:viewport-height
   #:viewport-width
   #:weight))
