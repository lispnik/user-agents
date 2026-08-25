;;;; data.lisp --- Loading and normalizing the vendored upstream dataset.
;;;;
;;;; The dataset ships as the gzipped JSON blob that upstream generates
;;;; (src/user-agents.json.gz).  We decompress and parse it lazily on first use
;;;; so that merely loading the system stays cheap.
;;;;
;;;; JSON objects become plists whose keys are kebab-case keywords ("screenHeight"
;;;; becomes :SCREEN-HEIGHT), JSON null becomes NIL, and key order is preserved
;;;; so a record round-trips readably.

(in-package #:user-agents)

(define-condition user-agents-error (error) ()
  (:documentation "Superclass of every error signalled by this library."))

(define-condition dataset-error (user-agents-error)
  ((format-control :initarg :format-control :reader dataset-error-format-control)
   (format-arguments :initarg :format-arguments :initform '()
                     :reader dataset-error-format-arguments))
  (:report (lambda (condition stream)
             (apply #'format stream
                    (dataset-error-format-control condition)
                    (dataset-error-format-arguments condition))))
  (:documentation "Signalled when the dataset cannot be read or makes no sense."))

(defun dataset-error (format-control &rest format-arguments)
  (error 'dataset-error :format-control format-control
                        :format-arguments format-arguments))

(defvar *data-file* nil
  "Pathname of the gzipped JSON dataset to load.

NIL, the default, means the copy vendored with this system under data/.  Set
this to a freshly downloaded upstream file and call RELOAD-DATA to use it.")

(defun default-data-file ()
  "Pathname of the dataset vendored with this system."
  (asdf:system-relative-pathname "user-agents" "data/user-agents.json.gz"))

(defun data-file ()
  (or *data-file* (default-data-file)))

;;; ---------------------------------------------------------------------------
;;; JSON -> plist normalization

(defun camel-case-to-keyword (name)
  "Convert a camelCase JSON key such as \"screenHeight\" to :SCREEN-HEIGHT."
  (let ((out (make-string-output-stream)))
    (loop for i below (length name)
          for char = (char name i)
          do (when (and (upper-case-p char)
                        (plusp i)
                        (not (upper-case-p (char name (1- i)))))
               (write-char #\- out))
             (write-char (char-upcase char) out))
    (intern (get-output-stream-string out) :keyword)))

(defun normalize-json-value (value)
  "Recursively turn jzon output into plists, lists and native Lisp scalars."
  (typecase value
    (hash-table
     ;; jzon iterates in insertion order, so records keep their upstream field
     ;; order.
     (let ((plist '()))
       (maphash (lambda (key sub)
                  (push (camel-case-to-keyword key) plist)
                  (push (normalize-json-value sub) plist))
                value)
       (nreverse plist)))
    (string value)
    (vector (map 'list #'normalize-json-value value))
    ;; jzon renders JSON null as the symbol NULL and false as NIL.
    (symbol (if (eq value 'null) nil value))
    (t value)))

(defun read-gzipped-json (pathname)
  "Decompress PATHNAME and parse its contents as JSON."
  (unless (probe-file pathname)
    (dataset-error "The user agent dataset ~a does not exist." pathname))
  (with-open-file (in pathname :element-type '(unsigned-byte 8))
    (let ((octets (chipz:decompress nil 'chipz:gzip in)))
      (com.inuoe.jzon:parse (babel:octets-to-string octets :encoding :utf-8)))))

(defun load-user-agents (&optional (pathname (data-file)))
  "Read PATHNAME and return a simple-vector of normalized user agent plists."
  (let ((records (normalize-json-value (read-gzipped-json pathname))))
    (unless (and (consp records) (every #'consp records))
      (dataset-error "~a does not contain a JSON array of user agent objects."
                     pathname))
    (coerce records 'simple-vector)))

;;; ---------------------------------------------------------------------------
;;; Lazy, thread-safe cache

(defvar %data-lock (bordeaux-threads:make-recursive-lock "user-agents data")
  "Guards the dataset and pool caches.

Recursive on purpose: DEFAULT-POOL holds it while BUILD-POOL asks for the
dataset, which acquires it again when the dataset has not been loaded yet.")
(defvar %user-agents nil
  "Cached simple-vector of user agent plists, or NIL when not yet loaded.")
(defvar %default-pool nil
  "Cached unfiltered pool, invalidated whenever the dataset is reloaded.")

(defun all-user-agents ()
  "Return the whole dataset as a simple-vector of plists, loading it if needed.

The vector and the plists in it are shared; treat them as read-only.  Use
USER-AGENT-DATA or TOP when you want copies you may modify."
  (or %user-agents
      (bordeaux-threads:with-recursive-lock-held (%data-lock)
        (or %user-agents
            (setf %user-agents (load-user-agents))))))

(defun user-agent-count ()
  "Number of records in the dataset."
  (length (all-user-agents)))

(defun reload-data (&optional pathname)
  "Re-read the dataset, optionally from PATHNAME, and discard cached pools.

Returns the number of records loaded."
  (bordeaux-threads:with-recursive-lock-held (%data-lock)
    (when pathname
      (setf *data-file* (pathname pathname)))
    (let ((records (load-user-agents (data-file))))
      (setf %user-agents records
            %default-pool nil)
      (length records))))

;;; ---------------------------------------------------------------------------
;;; Record helpers

(defun getf-present (plist key)
  "Like GETF, but the second value says whether KEY was actually found."
  (loop for (k v) on plist by #'cddr
        when (eq k key)
          do (return (values v t))
        finally (return (values nil nil))))

(defun record-plist-p (object)
  "True when OBJECT looks like a normalized record: a plist with a keyword key."
  (and (consp object) (keywordp (car object))))

(defun copy-record (record)
  "Return a fresh copy of RECORD, copying nested record plists too."
  (loop for (key value) on record by #'cddr
        collect key
        collect (if (record-plist-p value) (copy-record value) value)))
