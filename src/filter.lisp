;;;; filter.lisp --- The filter DSL used to narrow the dataset.
;;;;
;;;; A filter is compiled into a one-argument predicate that is applied to a
;;;; value: either a whole user agent record, or -- when a filter descends into
;;;; a field -- the value of that field.  The forms a filter may take are:
;;;;
;;;;   NIL or T          matches anything (i.e. no constraint)
;;;;   a function        called with the value; its return value is the answer
;;;;   a REGEX object    see the REGEX constructor below
;;;;   a string          EQUAL against the value, or against the value's
;;;;                     :user-agent field when the value is a whole record
;;;;   a keyword         like a string, but compared case-insensitively
;;;;   a number          numerically = against the value
;;;;   a plist           (:key filter :key filter ...) -- every field must match
;;;;   a list of filters (filter filter ...)           -- every filter must match
;;;;
;;;; A list is read as a plist when its first element is a keyword and as a
;;;; conjunction of filters otherwise.  ALL-OF, ANY-OF and NONE-OF build
;;;; combinations explicitly when that inference is not what you want.

(in-package #:user-agents)

;;; ---------------------------------------------------------------------------
;;; Regular expression filters

(defstruct (regex (:constructor %make-regex (source scanner))
                  (:copier nil)
                  (:predicate regex-p)
                  (:print-object print-regex))
  (source "" :type string :read-only t)
  (scanner nil :read-only t))

(defun print-regex (regex stream)
  (print-unreadable-object (regex stream :type t)
    (prin1 (regex-source regex) stream)))

(defun regex (pattern &key case-insensitive)
  "Build a filter matching values against the regular expression PATTERN.

PATTERN is a cl-ppcre regular expression.  It is a partial match, like
JavaScript's RegExp.prototype.test: the pattern may match anywhere in the value.
When the value being tested is a whole user agent record, the pattern is applied
to its :user-agent string.

  (make-user-agent (regex \"Firefox/1[0-9][0-9]\"))
  (make-user-agent (list (regex \"Macintosh\") '(:device-category :desktop)))"
  (check-type pattern string)
  (%make-regex pattern (cl-ppcre:create-scanner pattern
                                                :case-insensitive-mode case-insensitive)))

;;; ---------------------------------------------------------------------------
;;; Explicit combinations

(defstruct (filter-combination (:constructor %make-filter-combination (kind filters))
                               (:copier nil)
                               (:predicate filter-combination-p))
  (kind :all :type (member :all :any :none) :read-only t)
  (filters '() :type list :read-only t))

(defun all-of (&rest filters)
  "A filter matching values that satisfy every one of FILTERS."
  (%make-filter-combination :all filters))

(defun any-of (&rest filters)
  "A filter matching values that satisfy at least one of FILTERS."
  (%make-filter-combination :any filters))

(defun none-of (&rest filters)
  "A filter matching values that satisfy none of FILTERS."
  (%make-filter-combination :none filters))

;;; ---------------------------------------------------------------------------
;;; Compilation

(defun scalar-comparison-target (value)
  "The string a scalar filter should be compared against, or NIL.

Whole records are compared through their :user-agent field, mirroring upstream;
numbers are compared by their printed representation so that, say, a regex can
be applied to a screen dimension."
  (cond ((record-plist-p value) (getf value :user-agent))
        ((stringp value) value)
        ((numberp value) (princ-to-string value))
        (t nil)))

(defun compile-regex-filter (regex)
  (let ((scanner (regex-scanner regex)))
    (lambda (value)
      (let ((string (scalar-comparison-target value)))
        (and string (cl-ppcre:scan scanner string) t)))))

(defun compile-string-filter (string)
  (lambda (value)
    (let ((target (scalar-comparison-target value)))
      (and target (string= string target)))))

(defun compile-keyword-filter (keyword)
  (let ((name (symbol-name keyword)))
    (lambda (value)
      (let ((target (scalar-comparison-target value)))
        (and target (string-equal name target))))))

(defun compile-number-filter (number)
  (lambda (value)
    (and (numberp value) (= number value))))

(defun compile-plist-filter (plist)
  "Compile (:key filter ...) into a predicate requiring every field to match."
  (let ((clauses (loop for (key subfilter) on plist by #'cddr
                       collect (cons key (compile-filter subfilter)))))
    (lambda (value)
      (and (record-plist-p value)
           (loop for (key . predicate) in clauses
                 always (multiple-value-bind (subvalue presentp)
                            (getf-present value key)
                          (and presentp (funcall predicate subvalue))))))))

(defun compile-conjunction (filters)
  (let ((predicates (mapcar #'compile-filter filters)))
    (lambda (value)
      (every (lambda (predicate) (funcall predicate value)) predicates))))

(defun compile-disjunction (filters)
  (let ((predicates (mapcar #'compile-filter filters)))
    (lambda (value)
      (some (lambda (predicate) (funcall predicate value)) predicates))))

(defun compile-filter (filter)
  "Compile FILTER into a one-argument predicate.

See the commentary at the top of this file for the accepted filter forms."
  (typecase filter
    (null (constantly t))
    ((eql t) (constantly t))
    (function filter)
    (regex (compile-regex-filter filter))
    (filter-combination
     (let ((filters (filter-combination-filters filter)))
       (ecase (filter-combination-kind filter)
         (:all (compile-conjunction filters))
         (:any (compile-disjunction filters))
         (:none (let ((any (compile-disjunction filters)))
                  (lambda (value) (not (funcall any value))))))))
    (string (compile-string-filter filter))
    (keyword (compile-keyword-filter filter))
    (number (compile-number-filter filter))
    (cons (if (keywordp (car filter))
              (compile-plist-filter filter)
              (compile-conjunction filter)))
    (t (error 'dataset-error
              :format-control "~s is not a valid user agent filter."
              :format-arguments (list filter)))))

(defun filter-matches-p (filter value)
  "True when VALUE satisfies FILTER.  Compiles FILTER on every call."
  (funcall (compile-filter filter) value))
