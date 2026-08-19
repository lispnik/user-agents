;;;; package.lisp --- Test package for the USER-AGENTS system.

(defpackage #:user-agents/tests
  (:use #:cl #:fiveam)
  (:local-nicknames (#:ua #:user-agents))
  (:export #:run-tests))

(in-package #:user-agents/tests)

(def-suite :user-agents
  :description "Test suite for the user-agents library.")

(defun run-tests ()
  "Run the whole suite; returns true when everything passed."
  (run! :user-agents))
