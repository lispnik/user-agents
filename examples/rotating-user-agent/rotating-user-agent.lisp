;;;; Send requests that look like they came from real browsers.
;;;;
;;;; Two libraries meet here. USER-AGENTS knows what real browsers claim to be,
;;;; weighted by how often each one is actually seen; CURLCL sends the request.
;;;; On their own each is half of the job -- a realistic user agent string that
;;;; nothing transmits, or a transmitter whose default string says "curlcl".
;;;;
;;;; The use this is written for is exercising a service you own: device
;;;; detection, a CDN's Vary handling, a redirect that only fires for mobile,
;;;; an analytics pipeline you want populated with a plausible client mix
;;;; rather than ten thousand identical rows. Point *ENDPOINT* at something
;;;; that is yours and the whole file is about your own service; the default is
;;;; a public echo endpoint so the examples run out of the box.
;;;;
;;;; The thing worth taking away is that both libraries have the same shape.
;;;; USER-AGENTS makes you build a POOL because filtering the dataset walks ten
;;;; thousand records, and CURLCL makes you open a SESSION because a connection,
;;;; a DNS answer and a TLS handshake are worth keeping. Build each once, use it
;;;; many times: SURVEY below does exactly that, and it is the difference
;;;; between a loop that is honest about its costs and one that pays them
;;;; repeatedly without saying so.
;;;;
;;;; A caveat the code cannot state for you: a real browser sends far more than
;;;; User-Agent. Accept, Accept-Language, and on Chromium the Sec-CH-UA client
;;;; hints all travel together, and a request whose User-Agent says Safari on
;;;; an iPhone while the rest of the headers say nothing at all is not
;;;; convincingly a browser to anything paying attention. This example sends
;;;; Accept-Language from the record, because the dataset carries it and it
;;;; would be odd to leave a matching field on the floor -- but it does not
;;;; pretend that two headers add up to a browser.
;;;;
;;;; Its own package, using only exported symbols, so that a hole in either
;;;; library's API fails here rather than being papered over with a `ua::'.

(defpackage #:rotating-user-agent
  (:use #:common-lisp)
  (:export #:*endpoint*
           #:fetch
           #:survey
           #:describe-draw
           #:report-device-mix))

(in-package #:rotating-user-agent)

(defparameter *endpoint* "https://httpbin.org/user-agent"
  "Where the examples send their requests.

A public echo endpoint, so that running this file needs nothing set up. The
point of the file is to aim it at a service of your own.")

;;; --- turning a record into request headers -------------------------------

(defun record-headers (agent)
  "The headers a request should carry to match AGENT, as an alist.

Only Accept-Language, and only when the record has a language -- some do not,
and inventing one would make the request less like its record rather than
more."
  (let ((language (ua:language agent)))
    (when language
      (list (cons "Accept-Language"
                  ;; A browser sends a preference list; the record has one
                  ;; language, so the honest rendering is that language
                  ;; followed by a lower-weighted wildcard.
                  (format nil "~A,~A;q=0.9,*;q=0.5"
                          language
                          (subseq language 0 (or (position #\- language)
                                                 (length language)))))))))

(defun describe-draw (agent)
  "A one-line summary of AGENT, for printing next to a result."
  (format nil "~A ~Ax~A~@[ ~A~] -- ~A"
          (ua:device-category agent)
          (ua:screen-width agent)
          (ua:screen-height agent)
          (ua:language agent)
          (ua:user-agent-string agent)))

;;; --- one request ---------------------------------------------------------

(defun fetch (&key filter (url *endpoint*) session)
  "GET URL as a randomly drawn browser.  Returns (values response agent).

FILTER is any USER-AGENTS filter, so the caller decides what kind of client
this should look like:

  (fetch)
  (fetch :filter '(:device-category :mobile))
  (fetch :filter (ua:regex \"Firefox\"))

Drawing per call is the right thing for one request and the wrong thing for a
run of them -- see SURVEY, which builds the pool once."
  (let ((agent (ua:random-user-agent filter)))
    (values (curl:http-get url
                           :user-agent (ua:user-agent-string agent)
                           :headers (record-headers agent)
                           :session session
                           ;; The endpoint is somebody else's; a transport
                           ;; failure on a GET is safe to repeat.
                           :retry '(:max-attempts 3 :initial-delay 0.3))
            agent)))

;;; --- many requests -------------------------------------------------------

(defun survey (count &key filter (url *endpoint*))
  "Send COUNT requests as COUNT different browsers, over one connection.

Returns a list of (agent . response-or-condition), in request order.

This is the shape the two libraries are built for. The pool is built once and
drawn from COUNT times, so the dataset is walked once rather than COUNT times;
the session is opened once, so the connection, the DNS answer and the TLS
handshake are established once rather than COUNT times. Both savings are the
same idea, and neither happens if you call FETCH in a loop.

REQUEST-MANY returns a condition in the slot of a request that failed instead
of aborting the batch, so a single refused connection does not cost you the
other results; the caller sees which is which by type."
  (let* ((pool (ua:make-pool filter))
         (agents (loop repeat count collect (ua:random-user-agent pool))))
    (curl:with-session (session)
      (let ((responses
              (curl:request-many
               (mapcar (lambda (agent)
                         (list url
                               :user-agent (ua:user-agent-string agent)
                               :headers (record-headers agent)))
                       agents)
               :session session
               :retry '(:max-attempts 3 :initial-delay 0.3))))
        (mapcar #'cons agents responses)))))

;;; --- what a realistic mix actually looks like ----------------------------

(defun report-device-mix (count &key filter (stream *standard-output*))
  "Draw COUNT user agents and print how they break down by device category.

No requests: this one is about the dataset rather than the network. It is here
because the weighting is the part people do not believe until they see it --
draw a thousand and the split lands near the real-world one, which is the whole
reason to prefer this over a hand-written list of ten user agent strings.

TOP shows the other side of the same distribution: the individual records
carrying the most weight, which are what a weighted draw returns most often."
  (let ((counts (make-hash-table :test #'equal))
        (pool (ua:make-pool filter)))
    (dotimes (i count)
      (incf (gethash (ua:device-category (ua:random-user-agent pool)) counts 0)))
    (format stream "~&~:D draw~:P from a pool of ~:D record~:P:~%"
            count (ua:pool-size pool))
    (let ((rows (sort (loop for category being the hash-keys of counts
                              using (hash-value n)
                            collect (cons category n))
                      #'> :key #'cdr)))
      (dolist (row rows)
        (format stream "  ~12A ~6,2F%~%" (car row) (* 100 (/ (cdr row) count)))))
    (format stream "~&Heaviest single records:~%")
    (dolist (record (ua:top 3 pool))
      (format stream "  ~,6F  ~A~%"
              (getf record :weight) (getf record :user-agent)))
    (values)))
