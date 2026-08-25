;;;; user-agents.asd

(defsystem "user-agents"
  :description "Random user agent generation from real-world usage statistics."
  :long-description "A Common Lisp port of the intoli/user-agents JavaScript
library.  It vendors the same upstream dataset of real user agents and picks
from it at random, weighted by how often each one is actually observed in the
wild, with a filter DSL for narrowing the pool by device category, platform,
screen size or anything else in a record."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "BSD-2-Clause"
  :homepage "https://github.com/intoli/user-agents"
  :version (:read-file-form "version.sexp")
  :depends-on ("com.inuoe.jzon"
               "chipz"
               "babel"
               "cl-ppcre"
               "bordeaux-threads")
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "version")
                             (:file "data")
                             (:file "filter")
                             (:file "user-agent")
                             (:file "fields")))
               (:static-file "data/user-agents.json.gz")
               (:static-file "data/upstream.sexp")
               (:static-file "README.md")
               (:static-file "LICENSE")
               (:static-file "LICENSE.upstream"))
  :in-order-to ((test-op (test-op "user-agents/tests"))))

(defsystem "user-agents/examples"
  :description "Worked examples: user-agents combined with other libraries."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "BSD-2-Clause"
  :version (:read-file-form "version.sexp")
  :depends-on ("user-agents" "curlcl")
  ;; Each example lives in its own package and uses only exported symbols.
  ;; That is the point of them being a system rather than loose scripts: if an
  ;; example needs a `user-agents::' symbol, the API has a hole, and loading
  ;; this is what makes that fail loudly.
  :components ((:module "examples"
                :components ((:module "rotating-user-agent"
                              :components ((:file "rotating-user-agent")))))))

(defsystem "user-agents/tests"
  :description "Test suite for the user-agents system."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "BSD-2-Clause"
  :depends-on ("user-agents" "fiveam" "ironclad" "com.inuoe.jzon")
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "tests"))))
  :perform (test-op (operation system)
             (declare (ignore operation system))
             (unless (uiop:symbol-call :fiveam :run! :user-agents)
               (error "Some user-agents tests failed."))))
