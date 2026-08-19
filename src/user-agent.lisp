;;;; user-agent.lisp --- Pools and weighted random user agent generation.
;;;;
;;;; A POOL is the set of records matching a filter, together with the
;;;; renormalized cumulative weight distribution over them.  Building a pool is
;;;; the expensive part -- it walks the whole dataset -- so a pool is built once
;;;; and then sampled as often as you like.  A USER-AGENT remembers the pool it
;;;; came from, which is what makes RANDOMIZE and NEXT-USER-AGENT cheap.

(in-package #:user-agents)

(define-condition no-matching-user-agents (user-agents-error)
  ((filter :initarg :filter :initform nil :reader no-matching-user-agents-filter))
  (:report (lambda (condition stream)
             (format stream "No user agents matched the filter ~s."
                     (no-matching-user-agents-filter condition))))
  (:documentation "Signalled when a filter selects no records at all."))

;;; ---------------------------------------------------------------------------
;;; Pools

(deftype index-vector () '(simple-array (unsigned-byte 32) (*)))
(deftype weight-vector () '(simple-array double-float (*)))

(defstruct (pool (:constructor %make-pool (filter indices weights cumulative))
                 (:copier nil)
                 (:predicate poolp)
                 (:print-object print-pool))
  "A filtered slice of the dataset with its weights renormalized to sum to 1."
  (filter nil :read-only t)
  (indices #.(make-array 0 :element-type '(unsigned-byte 32))
   :type index-vector :read-only t)
  (weights #.(make-array 0 :element-type 'double-float)
   :type weight-vector :read-only t)
  (cumulative #.(make-array 0 :element-type 'double-float)
   :type weight-vector :read-only t))

(defun print-pool (pool stream)
  (print-unreadable-object (pool stream :type t)
    (format stream "~d record~:p~@[ matching ~s~]"
            (pool-size pool) (pool-filter pool))))

(defun pool-size (pool)
  "Number of records in POOL."
  (length (pool-indices pool)))

(defun pool-entries (pool)
  "A list of fresh copies of the records in POOL, in dataset order."
  (let ((dataset (all-user-agents)))
    (map 'list (lambda (index) (copy-record (svref dataset index)))
         (pool-indices pool))))

(defun record-weight (record)
  "The non-negative weight of RECORD, defaulting to 0 when it has none."
  (let ((weight (getf record :weight)))
    (if (and (realp weight) (plusp weight))
        (coerce weight 'double-float)
        0d0)))

(defun build-pool (filter)
  "Walk the dataset and build the pool of records matching FILTER."
  (let* ((dataset (all-user-agents))
         (predicate (compile-filter filter))
         (matches '())
         (count 0))
    (loop for index from 0 below (length dataset)
          for record = (svref dataset index)
          when (funcall predicate record)
            do (push index matches)
               (incf count))
    (when (zerop count)
      (error 'no-matching-user-agents :filter filter))
    (setf matches (nreverse matches))
    (let ((indices (make-array count :element-type '(unsigned-byte 32)))
          (weights (make-array count :element-type 'double-float))
          (cumulative (make-array count :element-type 'double-float))
          (total 0d0))
      (loop for index in matches
            for i from 0
            for weight = (record-weight (svref dataset index))
            do (setf (aref indices i) index
                     (aref weights i) weight)
               (incf total weight))
      ;; Upstream divides by the total weight; if every match happens to carry a
      ;; zero weight that would produce NaNs, so fall back to a uniform draw.
      (when (zerop total)
        (fill weights 1d0)
        (setf total (coerce count 'double-float)))
      (let ((running 0d0))
        (dotimes (i count)
          (setf (aref weights i) (/ (aref weights i) total))
          (incf running (aref weights i))
          (setf (aref cumulative i) running))
        ;; Guard against floating point drift leaving the last entry below 1.
        (setf (aref cumulative (1- count)) 1d0))
      (%make-pool filter indices weights cumulative))))

(defun default-pool ()
  "The cached pool covering the whole dataset."
  (or %default-pool
      (bordeaux-threads:with-lock-held (%data-lock)
        (or %default-pool
            (setf %default-pool (build-pool nil))))))

(defun make-pool (&optional filter)
  "Build the pool of records matching FILTER.

FILTER defaults to NIL, which selects the whole dataset and returns a cached
pool.  Signals NO-MATCHING-USER-AGENTS when nothing matches."
  (if (null filter)
      (default-pool)
      (build-pool filter)))

(defun resolve-pool (filter-or-pool)
  (if (poolp filter-or-pool) filter-or-pool (make-pool filter-or-pool)))

;;; ---------------------------------------------------------------------------
;;; Weighted sampling

(defun sample-index (pool)
  "Draw a dataset index from POOL according to its weight distribution."
  (declare (optimize (speed 3) (safety 1)))
  (let* ((cumulative (pool-cumulative pool))
         (r (random 1d0))
         (low 0)
         (high (1- (length cumulative))))
    (declare (type weight-vector cumulative) (type double-float r))
    ;; Smallest index whose cumulative weight exceeds R.
    (loop while (< low high)
          do (let ((mid (ash (+ low high) -1)))
               (if (> (aref cumulative mid) r)
                   (setf high mid)
                   (setf low (1+ mid)))))
    (aref (pool-indices pool) low)))

;;; ---------------------------------------------------------------------------
;;; User agents

(defstruct (user-agent (:constructor %make-user-agent (pool data))
                       (:copier nil)
                       (:predicate user-agent-p)
                       (:print-object print-user-agent))
  "One randomly drawn user agent record, plus the pool it was drawn from."
  (pool nil :type pool :read-only t)
  (data '() :type list))

(defun print-user-agent (user-agent stream)
  (print-unreadable-object (user-agent stream :type t)
    (prin1 (user-agent-string user-agent) stream)))

(defun user-agent-string (user-agent)
  "The User-Agent header string of USER-AGENT."
  (getf (user-agent-data user-agent) :user-agent))

(defun randomize (user-agent)
  "Draw a new record into USER-AGENT from its own pool.  Returns USER-AGENT."
  (let ((dataset (all-user-agents))
        (pool (user-agent-pool user-agent)))
    (setf (user-agent-data user-agent)
          (copy-record (svref dataset (sample-index pool)))))
  user-agent)

(defun make-user-agent (&optional filter)
  "Return a random user agent drawn from the records matching FILTER.

FILTER defaults to NIL, meaning the whole dataset; see COMPILE-FILTER for the
filter forms.  Signals NO-MATCHING-USER-AGENTS when nothing matches.

  (make-user-agent)
  (make-user-agent '(:device-category :mobile))
  (make-user-agent (regex \"Chrome\"))"
  (random-user-agent filter))

(defun random-user-agent (&optional filter-or-pool)
  "Return a random user agent from FILTER-OR-POOL, a filter or an existing POOL.

Passing a pool skips the dataset walk, so it is the cheap way to draw many user
agents under the same filter."
  (let ((pool (resolve-pool filter-or-pool)))
    (randomize (%make-user-agent pool '()))))

(defun next-user-agent (user-agent)
  "Return a fresh user agent drawn from the same pool as USER-AGENT."
  (random-user-agent (user-agent-pool user-agent)))

(defun top (&optional count filter-or-pool)
  "The COUNT heaviest records matching FILTER-OR-POOL, heaviest first.

COUNT defaults to every matching record.  FILTER-OR-POOL may be a filter, a
POOL, or a USER-AGENT, in which case that user agent's pool is used.  Returns a
list of fresh record plists."
  (let* ((pool (if (user-agent-p filter-or-pool)
                   (user-agent-pool filter-or-pool)
                   (resolve-pool filter-or-pool)))
         (size (pool-size pool))
         (weights (pool-weights pool))
         (indices (pool-indices pool))
         (dataset (all-user-agents))
         (order (make-array size)))
    (dotimes (i size)
      (setf (aref order i) i))
    (setf order (sort order #'> :key (lambda (i) (aref weights i))))
    (let ((n (if count (min count size) size)))
      (loop for rank from 0 below n
            collect (copy-record (svref dataset (aref indices (aref order rank))))))))
