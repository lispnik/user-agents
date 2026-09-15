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
  "1.0.26"
  "Version of this Common Lisp port. The patch component is bumped automatically whenever the vendored upstream dataset changes.")

(defparameter *upstream-version*
  "2.1.184"
  "Version of the intoli/user-agents npm package the vendored dataset came from.")

(defparameter *data-sha256*
  "21e7d5829c83555f51eb07158befb086db4257afb021350dc69b0d1d2e6c8aa8"
  "SHA-256 of data/user-agents.json.gz, used to detect upstream changes.")

(defparameter *data-retrieved*
  "2026-09-15"
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
