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
  "1.0.16"
  "Version of this Common Lisp port. The patch component is bumped automatically whenever the vendored upstream dataset changes.")

(defparameter *upstream-version*
  "2.1.173"
  "Version of the intoli/user-agents npm package the vendored dataset came from.")

(defparameter *data-sha256*
  "213a80691966f35b1c851d700f6fbe805d75813a7d50f5a8a3d05c8507ac057a"
  "SHA-256 of data/user-agents.json.gz, used to detect upstream changes.")

(defparameter *data-retrieved*
  "2026-09-04"
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
