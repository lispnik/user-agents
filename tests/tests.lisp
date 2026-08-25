;;;; tests.lisp --- Test suite for the USER-AGENTS system.

(in-package #:user-agents/tests)

(in-suite :user-agents)

(defun a-record ()
  "Some arbitrary but stable record from the dataset."
  (svref (ua:all-user-agents) 0))

(defun record-named (user-agent-string)
  (find user-agent-string (ua:all-user-agents)
        :key (lambda (record) (getf record :user-agent))
        :test #'string=))

;;; ---------------------------------------------------------------------------
;;; The dataset

(test dataset-loads
  "The vendored dataset parses into a plausible set of records."
  (let ((dataset (ua:all-user-agents)))
    (is (typep dataset 'simple-vector))
    (is (plusp (length dataset)))
    (is (= (length dataset) (ua:user-agent-count)))))

(test every-record-is-well-formed
  "Every record is a keyword plist carrying at least a user agent and a weight."
  (let ((bad-plist 0) (bad-string 0) (bad-weight 0))
    (loop for record across (ua:all-user-agents)
          do (unless (and (consp record) (evenp (length record))
                          (loop for key in record by #'cddr always (keywordp key)))
               (incf bad-plist))
             (let ((string (getf record :user-agent)))
               (unless (and (stringp string) (plusp (length string)))
                 (incf bad-string)))
             (let ((weight (getf record :weight)))
               (unless (and (realp weight) (not (minusp weight)))
                 (incf bad-weight))))
    (is (zerop bad-plist) "~d record(s) are not keyword plists" bad-plist)
    (is (zerop bad-string) "~d record(s) lack a user agent string" bad-string)
    (is (zerop bad-weight) "~d record(s) lack a usable weight" bad-weight)))

(test json-keys-become-kebab-keywords
  (is (eq :screen-height (ua::camel-case-to-keyword "screenHeight")))
  (is (eq :user-agent (ua::camel-case-to-keyword "userAgent")))
  (is (eq :oscpu (ua::camel-case-to-keyword "oscpu")))
  (is (eq :rtt (ua::camel-case-to-keyword "rtt")))
  (is (eq :device-category (ua::camel-case-to-keyword "deviceCategory")))
  ;; Runs of capitals are not split, so "downlinkMax" and "URLs" both behave.
  (is (eq :downlink-max (ua::camel-case-to-keyword "downlinkMax"))))

(test json-null-becomes-nil
  (is (equal '(:a nil :b 1) (ua::normalize-json-value
                             (com.inuoe.jzon:parse "{\"a\":null,\"b\":1}")))))

;;; ---------------------------------------------------------------------------
;;; Generated version metadata

(test version-metadata-matches-the-vendored-data
  "The generated constants describe the data file that is actually shipped.

This is the contract scripts/update.lisp maintains: if it ever fails, the port
was released without re-running the updater."
  (let ((data-file (ua::default-data-file)))
    (is (probe-file data-file))
    (is (string-equal ua:*data-sha256*
                      (ironclad:byte-array-to-hex-string
                       (ironclad:digest-file :sha256 data-file))))
    (is (= ua:*data-record-count* (ua:user-agent-count)))))

(test version-sexp-matches-the-version-parameter
  "version.sexp, which ASDF reads, agrees with the compiled-in version."
  (let ((declared (with-open-file (in (asdf:system-relative-pathname
                                       "user-agents" "version.sexp"))
                    (let ((*read-eval* nil)) (read in)))))
    (is (equal declared ua:*version*))
    (is (equal declared (ua:version)))
    (is (equal declared (asdf:component-version (asdf:find-system "user-agents"))))))

(test upstream-sexp-matches-the-version-parameters
  (let ((metadata (with-open-file (in (asdf:system-relative-pathname
                                       "user-agents" "data/upstream.sexp"))
                    (let ((*read-eval* nil)) (read in)))))
    (is (string-equal ua:*data-sha256* (getf metadata :sha256)))
    (is (equal ua:*upstream-version* (getf metadata :upstream-version)))
    (is (= ua:*data-record-count* (getf metadata :record-count)))))

;;; ---------------------------------------------------------------------------
;;; Filters

(test nil-filter-matches-everything
  (is (ua:filter-matches-p nil (a-record)))
  (is (ua:filter-matches-p t (a-record)))
  (is (= (ua:user-agent-count) (ua:pool-size (ua:make-pool nil)))))

(test plist-filter-constrains-fields
  (let ((record (a-record)))
    (is (ua:filter-matches-p (list :platform (getf record :platform)) record))
    (is (not (ua:filter-matches-p '(:platform "No Such Platform") record)))
    ;; A field the record does not have never matches.
    (is (not (ua:filter-matches-p '(:no-such-field "x") record)))))

(test keyword-filter-values-are-case-insensitive
  (let ((pool (ua:make-pool '(:device-category :mobile))))
    (is (plusp (ua:pool-size pool)))
    (is (= (ua:pool-size pool)
           (ua:pool-size (ua:make-pool '(:device-category "mobile")))))
    (dolist (record (ua:pool-entries pool))
      (is (string= "mobile" (getf record :device-category))))))

(test nested-plist-filters-descend
  (let ((pool (ua:make-pool '(:connection (:effective-type "4g")))))
    (is (plusp (ua:pool-size pool)))
    (dolist (record (ua:pool-entries pool))
      (is (string= "4g" (getf (getf record :connection) :effective-type))))))

(test regex-filters-match-the-user-agent-string
  (let ((pool (ua:make-pool (ua:regex "Firefox"))))
    (is (plusp (ua:pool-size pool)))
    (dolist (record (ua:pool-entries pool))
      (is (search "Firefox" (getf record :user-agent)))))
  ;; Case insensitivity is opt-in.
  (is (ua:filter-matches-p (ua:regex "firefox" :case-insensitive t)
                           '(:user-agent "Mozilla/5.0 Firefox/1.0")))
  (is (not (ua:filter-matches-p (ua:regex "firefox")
                                '(:user-agent "Mozilla/5.0 Firefox/1.0")))))

(test regex-filters-descend-into-fields
  (let ((pool (ua:make-pool (list :platform (ua:regex "^Linux")))))
    (is (plusp (ua:pool-size pool)))
    (dolist (record (ua:pool-entries pool))
      (is (eql 0 (search "Linux" (getf record :platform)))))))

(test string-filter-compares-against-the-user-agent-of-a-record
  (let* ((record (a-record))
         (string (getf record :user-agent)))
    (is (ua:filter-matches-p string record))
    (is (not (ua:filter-matches-p "not a real user agent" record)))))

(test number-filters-compare-numerically
  (let ((record (a-record)))
    (is (ua:filter-matches-p (list :screen-width (getf record :screen-width)) record))
    (is (not (ua:filter-matches-p '(:screen-width -1) record)))))

(test function-filters-receive-the-record
  (let ((pool (ua:make-pool (lambda (record) (> (getf record :screen-width 0) 2000)))))
    (is (plusp (ua:pool-size pool)))
    (dolist (record (ua:pool-entries pool))
      (is (> (getf record :screen-width) 2000)))))

(test a-list-of-filters-is-a-conjunction
  (let* ((filter (list (ua:regex "Firefox") '(:device-category :desktop)))
         (pool (ua:make-pool filter)))
    (is (plusp (ua:pool-size pool)))
    (dolist (record (ua:pool-entries pool))
      (is (search "Firefox" (getf record :user-agent)))
      (is (string= "desktop" (getf record :device-category))))
    ;; ALL-OF spells the same thing out explicitly.
    (is (= (ua:pool-size pool)
           (ua:pool-size (ua:make-pool (ua:all-of (ua:regex "Firefox")
                                                  '(:device-category :desktop))))))))

(test any-of-is-a-disjunction
  (let ((mobile (ua:pool-size (ua:make-pool '(:device-category :mobile))))
        (tablet (ua:pool-size (ua:make-pool '(:device-category :tablet))))
        (either (ua:pool-size (ua:make-pool (ua:any-of '(:device-category :mobile)
                                                       '(:device-category :tablet))))))
    (is (plusp mobile))
    (is (plusp tablet))
    (is (= either (+ mobile tablet)))))

(test none-of-is-a-negation
  (let ((all (ua:user-agent-count))
        (mobile (ua:pool-size (ua:make-pool '(:device-category :mobile))))
        (not-mobile (ua:pool-size (ua:make-pool (ua:none-of '(:device-category :mobile))))))
    (is (= all (+ mobile not-mobile)))))

(test an-unmatchable-filter-signals
  (signals ua:no-matching-user-agents
    (ua:make-user-agent '(:platform "Commodore 64")))
  (signals ua:no-matching-user-agents
    (ua:make-pool (constantly nil)))
  (handler-case (ua:make-user-agent '(:platform "Commodore 64"))
    (ua:no-matching-user-agents (condition)
      (is (equal '(:platform "Commodore 64")
                 (ua:no-matching-user-agents-filter condition))))))

(test an-invalid-filter-signals
  (signals ua:user-agents-error (ua:compile-filter #\x)))

;;; ---------------------------------------------------------------------------
;;; Pools

(test the-unfiltered-pool-is-cached
  (is (eq (ua:make-pool) (ua:make-pool)))
  (is (eq (ua:make-pool) (ua:make-pool nil))))

(test pools-can-be-built-before-anything-touches-the-dataset
  "The first data access a program makes may well be MAKE-USER-AGENT itself.

DEFAULT-POOL holds the dataset lock while BUILD-POOL asks for the dataset,
which acquires it again when nothing has loaded it yet. Every other test in
this file masks that by reading the dataset first, so this one clears the
caches to reproduce a cold image. The LET bindings are thread-local, so the
caches the rest of the suite relies on are restored on the way out."
  (let ((user-agents::%user-agents nil)
        (user-agents::%default-pool nil))
    (is (ua:user-agent-p (ua:make-user-agent)))
    (is (= (ua:user-agent-count) (ua:pool-size (ua:make-pool)))))
  ;; The same, for a filtered pool, which reaches the dataset by a different
  ;; route: BUILD-POOL directly rather than through DEFAULT-POOL.
  (let ((user-agents::%user-agents nil)
        (user-agents::%default-pool nil))
    (is (plusp (ua:pool-size (ua:make-pool '(:device-category :mobile)))))))

(test pool-weights-form-a-normalized-distribution
  (dolist (filter (list nil '(:device-category :mobile) (ua:regex "Safari")))
    (let* ((pool (ua:make-pool filter))
           (weights (ua::pool-weights pool))
           (cumulative (ua::pool-cumulative pool)))
      (is (= (ua:pool-size pool) (length weights) (length cumulative)))
      (is (< (abs (- 1d0 (reduce #'+ weights))) 1d-9))
      (is (= 1d0 (aref cumulative (1- (length cumulative)))))
      ;; The cumulative distribution has to be non-decreasing for the binary
      ;; search in SAMPLE-INDEX to be correct.
      (is (loop for i from 1 below (length cumulative)
                always (<= (aref cumulative (1- i)) (aref cumulative i)))))))

(test pool-entries-are-copies
  (let* ((pool (ua:make-pool '(:device-category :desktop)))
         (entry (first (ua:pool-entries pool))))
    (setf (getf entry :platform) "tampered")
    (is (notany (lambda (record) (equal "tampered" (getf record :platform)))
                (ua:all-user-agents)))))

(test a-pool-can-be-reused-for-many-draws
  (let* ((pool (ua:make-pool '(:device-category :mobile)))
         (allowed (make-hash-table :test #'equal)))
    (dolist (record (ua:pool-entries pool))
      (setf (gethash (getf record :user-agent) allowed) t))
    (dotimes (i 200)
      (let ((user-agent (ua:random-user-agent pool)))
        (is (eq pool (ua:user-agent-pool user-agent)))
        (is (gethash (ua:user-agent-string user-agent) allowed))))))

;;; ---------------------------------------------------------------------------
;;; Sampling

(test sampling-respects-the-weights
  "Draws from a two-record pool should follow the recorded weight ratio."
  (let* ((dataset (ua:all-user-agents))
         (weighted (sort (loop for record across dataset
                               when (plusp (getf record :weight 0))
                                 collect record)
                         #'> :key (lambda (record) (getf record :weight))))
         (heavy (first weighted))
         (light (car (last weighted)))
         ;; Selecting by identity rather than by user agent string: the dataset
         ;; contains the same string more than once, with different screen sizes.
         (pool (ua:make-pool (lambda (record) (member record (list heavy light) :test #'eq))))
         (ratio (/ (getf heavy :weight) (+ (getf heavy :weight) (getf light :weight)))))
    (is (= 2 (ua:pool-size pool)))
    (is (> ratio 0.5))
    (let ((*random-state* (sb-ext:seed-random-state 20260819))
          (draws 4000)
          (heavy-count 0))
      (dotimes (i draws)
        (when (eq heavy (svref dataset (ua::sample-index pool)))
          (incf heavy-count)))
      (is (< (abs (- (/ heavy-count draws) ratio)) 0.05)
          "drew the heavy record ~,4f of the time, expected ~,4f"
          (/ heavy-count draws) ratio))))

(test sampling-is-roughly-uniform-for-equal-weights
  "A pool whose records all carry the same weight is drawn from evenly."
  (let* ((dataset (ua:all-user-agents))
         (buckets (make-hash-table))
         (chosen (loop for index from 0 below (min 8 (length dataset))
                       collect index)))
    ;; Build a pool by identity over the first few records, then override the
    ;; weights so the expected distribution is exactly uniform.
    (let* ((records (mapcar (lambda (index) (svref dataset index)) chosen))
           (pool (ua:make-pool (lambda (record) (member record records :test #'eq))))
           (size (ua:pool-size pool))
           (weights (ua::pool-weights pool))
           (cumulative (ua::pool-cumulative pool)))
      (dotimes (i size)
        (setf (aref weights i) (/ 1d0 size)
              (aref cumulative i) (/ (float (1+ i) 1d0) size)))
      (setf (aref cumulative (1- size)) 1d0)
      (let ((*random-state* (sb-ext:seed-random-state 99))
            (draws 20000))
        (dotimes (i draws)
          (incf (gethash (ua::sample-index pool) buckets 0)))
        (is (= size (hash-table-count buckets)))
        (maphash (lambda (index count)
                   (declare (ignore index))
                   (is (< (abs (- (/ count draws) (/ 1d0 size))) 0.02)
                       "bucket saw ~,4f of draws, expected ~,4f"
                       (/ count draws) (/ 1d0 size)))
                 buckets)))))

(test sampling-covers-the-whole-pool
  "Given enough draws from a small uniform-ish pool, every record shows up."
  (let* ((pool (ua:make-pool '(:device-category :tablet)))
         (seen (make-hash-table :test #'equal))
         (*random-state* (sb-ext:seed-random-state 7)))
    (dotimes (i 20000)
      (setf (gethash (ua:user-agent-string (ua:random-user-agent pool)) seen) t))
    (is (plusp (hash-table-count seen)))
    (is (<= (hash-table-count seen) (ua:pool-size pool)))))

(test sample-index-always-lands-inside-the-pool
  (let* ((pool (ua:make-pool '(:vendor "Apple Computer, Inc.")))
         (indices (ua::pool-indices pool))
         (members (make-hash-table)))
    (loop for index across indices do (setf (gethash index members) t))
    (dotimes (i 1000)
      (is (gethash (ua::sample-index pool) members)))))

;;; ---------------------------------------------------------------------------
;;; User agents

(test make-user-agent-produces-a-usable-record
  (let ((user-agent (ua:make-user-agent)))
    (is (ua:user-agent-p user-agent))
    (is (stringp (ua:user-agent-string user-agent)))
    (is (plusp (length (ua:user-agent-string user-agent))))
    (is (equal (ua:user-agent-string user-agent)
               (getf (ua:user-agent-data user-agent) :user-agent)))
    (is (search (ua:user-agent-string user-agent)
                (princ-to-string user-agent)))))

(test user-agent-data-is-a-copy
  (let ((user-agent (ua:make-user-agent)))
    (setf (getf (ua:user-agent-data user-agent) :platform) "tampered")
    (is (notany (lambda (record) (equal "tampered" (getf record :platform)))
                (ua:all-user-agents)))))

(test randomize-redraws-in-place
  (let* ((user-agent (ua:make-user-agent '(:device-category :desktop)))
         (pool (ua:user-agent-pool user-agent))
         (strings (make-hash-table :test #'equal)))
    (dotimes (i 100)
      (is (eq user-agent (ua:randomize user-agent)))
      (is (eq pool (ua:user-agent-pool user-agent)))
      (is (string= "desktop" (ua:device-category user-agent)))
      (setf (gethash (ua:user-agent-string user-agent) strings) t))
    ;; 100 weighted draws from a large pool should not all collapse to one value.
    (is (> (hash-table-count strings) 1))))

(test next-user-agent-keeps-the-pool
  (let* ((first (ua:make-user-agent (ua:regex "Android")))
         (second (ua:next-user-agent first)))
    (is (eq (ua:user-agent-pool first) (ua:user-agent-pool second)))
    (is (search "Android" (ua:user-agent-string second)))))

(test random-user-agent-accepts-a-filter-or-a-pool
  (is (search "iPhone" (ua:user-agent-string (ua:random-user-agent (ua:regex "iPhone")))))
  (let ((pool (ua:make-pool (ua:regex "iPhone"))))
    (is (search "iPhone" (ua:user-agent-string (ua:random-user-agent pool))))))

;;; ---------------------------------------------------------------------------
;;; TOP

(test top-returns-the-heaviest-records-first
  (let ((records (ua:top 25)))
    (is (= 25 (length records)))
    (is (loop for (a b) on records while b
              always (>= (getf a :weight) (getf b :weight))))))

(test top-is-bounded-by-the-pool-size
  (let* ((pool (ua:make-pool '(:device-category :tablet)))
         (size (ua:pool-size pool)))
    (is (= size (length (ua:top nil pool))))
    (is (= size (length (ua:top (* 10 size) pool))))
    (is (= 1 (length (ua:top 1 pool))))))

(test top-accepts-a-user-agent
  (let ((user-agent (ua:make-user-agent '(:device-category :mobile))))
    (dolist (record (ua:top 5 user-agent))
      (is (string= "mobile" (getf record :device-category))))))

(test top-returns-copies
  (let ((record (first (ua:top 1))))
    (setf (getf record :user-agent) "tampered")
    (is (notany (lambda (r) (equal "tampered" (getf r :user-agent)))
                (ua:all-user-agents)))))

;;; ---------------------------------------------------------------------------
;;; Field access

(test field-reads-plain-and-nested-paths
  (let ((user-agent (ua:make-user-agent '(:connection (:effective-type "4g")))))
    (is (equal (ua:platform user-agent) (ua:field user-agent :platform)))
    (is (string= "4g" (ua:field user-agent '(:connection :effective-type))))
    (is (eq :missing (ua:field user-agent :no-such-field :missing)))
    (is (eq :missing (ua:field user-agent '(:connection :no-such-field) :missing)))
    (is (eq :missing (ua:field user-agent '(:no-such-field :deeper) :missing)))))

(test field-works-on-raw-records-too
  (let ((record (a-record)))
    (is (equal (getf record :platform) (ua:field record :platform)))))

(test named-accessors-agree-with-field
  (let ((user-agent (ua:make-user-agent)))
    (dolist (name '(:app-name :device-category :platform :screen-height
                    :screen-width :vendor :viewport-height :viewport-width :weight))
      (is (equal (ua:field user-agent name)
                 (funcall (find-symbol (symbol-name name) '#:user-agents) user-agent))))))

;;; ---------------------------------------------------------------------------
;;; Reloading

(test reload-data-rereads-the-file-and-drops-cached-pools
  (let ((before (ua:make-pool)))
    (is (= (ua:user-agent-count) (ua:reload-data)))
    (is (not (eq before (ua:make-pool))))
    (is (= (ua:user-agent-count) (ua:pool-size (ua:make-pool))))))
