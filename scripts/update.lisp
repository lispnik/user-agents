;;;; update.lisp --- Vendor a new upstream dataset and version the port for it.
;;;;
;;;; This script deliberately does not load the USER-AGENTS system: it must keep
;;;; working even when the library is mid-edit, and it is what generates
;;;; src/version.lisp in the first place.  It only needs the three libraries
;;;; required to hash, decompress and parse the candidate file.
;;;;
;;;; It is driven by environment variables rather than command line arguments so
;;;; that it can be loaded with plain `sbcl --load', which reads the user init
;;;; file and therefore sees the ocicl system registry:
;;;;
;;;;   UA_NEW_DATA          path to the freshly downloaded user-agents.json.gz
;;;;   UA_UPSTREAM_VERSION  version string from the upstream package.json
;;;;   UA_SOURCE_URL        URL the file came from
;;;;   UA_RESULT_FILE       optional; shell-sourceable summary is written here

(require :asdf)

(asdf:load-system :ironclad)
(asdf:load-system :chipz)
(asdf:load-system :babel)
(asdf:load-system :com.inuoe.jzon)

(defpackage #:user-agents-updater
  (:use #:cl)
  (:export #:main))

(in-package #:user-agents-updater)

(defparameter *root* (uiop:getcwd)
  "Repository root; the script is expected to run from there.")

(defun repo-file (relative)
  (merge-pathnames relative *root*))

(defun env (name &optional default)
  (let ((value (uiop:getenv name)))
    (if (and value (plusp (length value))) value default)))

;;; ---------------------------------------------------------------------------
;;; Reading and writing the small metadata files

(defun read-single-form (pathname &optional default)
  (if (probe-file pathname)
      (with-open-file (in pathname :external-format :utf-8)
        (let ((*read-eval* nil))
          (read in nil default)))
      default))

(defun write-form (pathname form header)
  (with-open-file (out pathname :direction :output :if-exists :supersede
                                :if-does-not-exist :create :external-format :utf-8)
    (format out ";;;; ~a~%" header)
    (let ((*print-readably* nil) (*print-pretty* t) (*print-case* :downcase))
      (prin1 form out))
    (terpri out)))

(defun parse-version (string)
  "Split \"1.2.3\" into the list (1 2 3), defaulting to (1 0 0)."
  (or (ignore-errors
       (let ((parts (uiop:split-string (string-trim " " string) :separator ".")))
         (when (= 3 (length parts))
           (mapcar #'parse-integer parts))))
      (list 1 0 0)))

(defun format-version (parts)
  (format nil "~{~d~^.~}" parts))

(defun bump-patch (string)
  (let ((parts (parse-version string)))
    (format-version (list (first parts) (second parts) (1+ (third parts))))))

(defun today ()
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (declare (ignore second minute hour))
    (format nil "~4,'0d-~2,'0d-~2,'0d" year month day)))

;;; ---------------------------------------------------------------------------
;;; Inspecting the candidate dataset

(defun sha256-file (pathname)
  (ironclad:byte-array-to-hex-string (ironclad:digest-file :sha256 pathname)))

(defun validate-dataset (pathname)
  "Parse PATHNAME and return its record count, refusing anything implausible.

The point is to never version and publish a dataset we cannot actually read."
  (let* ((octets (with-open-file (in pathname :element-type '(unsigned-byte 8))
                   (chipz:decompress nil 'chipz:gzip in)))
         (records (com.inuoe.jzon:parse (babel:octets-to-string octets :encoding :utf-8))))
    (unless (and (vectorp records) (not (stringp records)))
      (error "~a is not a JSON array." pathname))
    (let ((count (length records)))
      (when (< count 100)
        (error "~a holds only ~d record~:p; refusing to treat that as valid."
               pathname count))
      (loop for record across records
            for i from 0
            do (unless (hash-table-p record)
                 (error "Record ~d of ~a is not an object." i pathname))
               (unless (gethash "userAgent" record)
                 (error "Record ~d of ~a has no userAgent field." i pathname)))
      count)))

(defun copy-file (from to)
  (with-open-file (in from :element-type '(unsigned-byte 8))
    (with-open-file (out to :direction :output :element-type '(unsigned-byte 8)
                            :if-exists :supersede :if-does-not-exist :create)
      (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8))))
        (loop for end = (read-sequence buffer in)
              while (plusp end)
              do (write-sequence buffer out :end end))))))

;;; ---------------------------------------------------------------------------
;;; Generated files

(defun write-version-source (pathname &key version upstream-version sha256
                                           retrieved record-count source-url)
  (with-open-file (out pathname :direction :output :if-exists :supersede
                                :if-does-not-exist :create :external-format :utf-8)
    (write-string ";;;; version.lisp --- GENERATED FILE, DO NOT EDIT.
;;;;
;;;; Written by scripts/update.lisp whenever the upstream dataset changes.
;;;; Edit that script, not this file.
;;;;
;;;; These are DEFPARAMETERs rather than constants on purpose: regenerating this
;;;; file and reloading it in a live image is a normal thing to do, and DEFCONSTANT
;;;; makes that an error.

(in-package #:user-agents)

" out)
    (flet ((emit (name value docstring)
             (format out "(defparameter ~a~%  ~s~%  ~s)~%~%"
                     name value docstring)))
      (emit "*version*" version
            "Version of this Common Lisp port. The patch component is bumped automatically whenever the vendored upstream dataset changes.")
      (emit "*upstream-version*" upstream-version
            "Version of the intoli/user-agents npm package the vendored dataset came from.")
      (emit "*data-sha256*" sha256
            "SHA-256 of data/user-agents.json.gz, used to detect upstream changes.")
      (emit "*data-retrieved*" retrieved
            "Date the vendored dataset was downloaded, as YYYY-MM-DD.")
      (emit "*data-record-count*" record-count
            "Number of user agent records in the vendored dataset.")
      (emit "*data-source-url*" source-url
            "URL the vendored dataset was downloaded from."))
    (format out "(defun version ()~%  ~s~%  *version*)~%"
            "Version string of this port, for example \"1.0.7\".")))

(defun prepend-changelog (pathname version upstream-version record-count sha256)
  (let* ((existing (if (probe-file pathname)
                       (uiop:read-file-string pathname)
                       (format nil "# Changelog~%")))
         (header "# Changelog")
         (body (string-left-trim '(#\Newline)
                                 (if (uiop:string-prefix-p header existing)
                                     (subseq existing (length header))
                                     existing)))
         (entry (format nil "~%## ~a - ~a~%~%~
                             - Vendored the upstream dataset from intoli/user-agents ~a.~%~
                             - ~:d user agent records; SHA-256 `~a`.~%~%"
                        version (today) upstream-version record-count sha256)))
    (with-open-file (out pathname :direction :output :if-exists :supersede
                                  :if-does-not-exist :create :external-format :utf-8)
      (write-string header out)
      (terpri out)
      (write-string entry out)
      (write-string body out))))

(defun write-result (changed version previous-sha256 new-sha256 record-count)
  (let ((path (env "UA_RESULT_FILE"))
        (github-output (env "GITHUB_OUTPUT")))
    (flet ((emit (stream)
             (format stream "CHANGED=~a~%VERSION=~a~%RECORDS=~d~%OLD_SHA256=~a~%NEW_SHA256=~a~%"
                     (if changed "true" "false") version record-count
                     (or previous-sha256 "") new-sha256)))
      (when path
        (with-open-file (out path :direction :output :if-exists :supersede
                                  :if-does-not-exist :create)
          (emit out)))
      (when github-output
        (with-open-file (out github-output :direction :output :if-exists :append
                                           :if-does-not-exist :create)
          (format out "changed=~a~%version=~a~%records=~d~%"
                  (if changed "true" "false") version record-count))))))

;;; ---------------------------------------------------------------------------

(defun main ()
  (let* ((new-data (or (env "UA_NEW_DATA")
                       (error "UA_NEW_DATA is not set.")))
         (upstream-version (env "UA_UPSTREAM_VERSION" "unknown"))
         (source-url (env "UA_SOURCE_URL"
                          "https://raw.githubusercontent.com/intoli/user-agents/master/src/user-agents.json.gz"))
         (data-target (repo-file "data/user-agents.json.gz"))
         (metadata-file (repo-file "data/upstream.sexp"))
         (version-file (repo-file "version.sexp"))
         (previous (read-single-form metadata-file))
         (previous-sha (getf previous :sha256))
         (current-version (or (read-single-form version-file) "1.0.0"))
         (new-sha (sha256-file new-data))
         (bootstrap (not (probe-file data-target))))
    (when (and (equal new-sha previous-sha) (not bootstrap))
      (format t "~&Dataset unchanged (sha256 ~a); staying at version ~a.~%"
              new-sha current-version)
      (write-result nil current-version previous-sha new-sha
                    (or (getf previous :record-count) 0))
      (return-from main 0))

    (let ((record-count (validate-dataset new-data))
          ;; A first import keeps the declared version; every later change to the
          ;; dataset is a new release of the port.
          (version (if bootstrap current-version (bump-patch current-version))))
      (ensure-directories-exist data-target)
      (copy-file new-data data-target)
      (write-form version-file version
                  "version.sexp --- GENERATED. Version of this port; read by user-agents.asd.")
      (write-form metadata-file
                  (list :upstream-version upstream-version
                        :sha256 new-sha
                        :retrieved (today)
                        :record-count record-count
                        :source-url source-url)
                  "upstream.sexp --- GENERATED. Provenance of data/user-agents.json.gz.")
      (write-version-source (repo-file "src/version.lisp")
                            :version version
                            :upstream-version upstream-version
                            :sha256 new-sha
                            :retrieved (today)
                            :record-count record-count
                            :source-url source-url)
      (prepend-changelog (repo-file "CHANGELOG.md")
                         version upstream-version record-count new-sha)
      (format t "~&Dataset updated: ~:d records, upstream ~a, sha256 ~a.~%~
                 Port version is now ~a.~%"
              record-count upstream-version new-sha version)
      (write-result t version previous-sha new-sha record-count)
      0)))

(uiop:quit (handler-case (main)
             (error (condition)
               (format *error-output* "~&update.lisp: ~a~%" condition)
               1)))
