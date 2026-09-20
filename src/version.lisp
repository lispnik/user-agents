;;;; version.lisp --- GENERATED FILE, DO NOT EDIT.
;;;;
;;;; Written by scripts/update.lisp whenever the upstream dataset changes.
;;;; Edit that script, not this file.
;;;;
;;;; These are DEFPARAMETERs rather than constants on purpose: regenerating this
;;;; file and reloading it in a live image is a normal thing to do, and DEFCONSTANT
;;;; makes that an error.

(in-package #:user-agents)

(defparameter *version*
  "1.0.30"
  "Version of this Common Lisp port. The patch component is bumped automatically whenever the vendored upstream dataset changes.")

(defparameter *upstream-version*
  "2.1.189"
  "Version of the intoli/user-agents npm package the vendored dataset came from.")

(defparameter *data-sha256*
  "8464e4876d3729568387bfde140599d3a96da4951c89a8f7f5d5b6d212e0deca"
  "SHA-256 of data/user-agents.json.gz, used to detect upstream changes.")

(defparameter *data-retrieved*
  "2026-09-20"
  "Date the vendored dataset was downloaded, as YYYY-MM-DD.")

(defparameter *data-record-count*
  10000
  "Number of user agent records in the vendored dataset.")

(defparameter *data-source-url*
  "https://raw.githubusercontent.com/intoli/user-agents/master/src/user-agents.json.gz"
  "URL the vendored dataset was downloaded from.")

(defun version ()
  "Version string of this port, for example \"1.0.7\"."
  *version*)
