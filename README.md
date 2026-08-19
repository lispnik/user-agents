# user-agents

[![Tests](https://github.com/lispnik/user-agents/actions/workflows/test.yml/badge.svg)](https://github.com/lispnik/user-agents/actions/workflows/test.yml)
[![Track upstream dataset](https://github.com/lispnik/user-agents/actions/workflows/update-data.yml/badge.svg)](https://github.com/lispnik/user-agents/actions/workflows/update-data.yml)

A Common Lisp port of [intoli/user-agents](https://github.com/intoli/user-agents).

It vendors the same dataset of real-world user agents that the upstream
JavaScript library ships, and draws from it at random *weighted by how often
each user agent is actually observed in the wild* — so a random draw looks like
real traffic rather than a uniform sample of exotic browsers. A filter DSL
narrows the pool by device category, platform, screen size, connection type, or
anything else recorded in a user agent record.

Tested on SBCL, dependencies managed with [ocicl](https://github.com/ocicl/ocicl),
tests written with [FiveAM](https://github.com/lispci/fiveam).

## Installation

```sh
git clone https://github.com/lispnik/user-agents.git
cd user-agents
ocicl install
```

Then, from a REPL started in that directory:

```lisp
(asdf:load-system :user-agents)
```

The package is `user-agents`, nicknamed `ua`.

## Quick start

```lisp
(ua:make-user-agent)
;=> #<USER-AGENT "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 ...">

(ua:user-agent-string (ua:make-user-agent))
;=> "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ... Chrome/144.0.0.0 Safari/537.36"

(ua:make-user-agent '(:device-category :mobile))
(ua:make-user-agent (ua:regex "Firefox"))
(ua:make-user-agent (lambda (record) (> (getf record :screen-width) 2000)))
```

A user agent carries the whole record it was drawn from, not just the header
string:

```lisp
(let ((agent (ua:make-user-agent '(:device-category :desktop))))
  (list (ua:platform agent)                          ; => "MacIntel"
        (ua:screen-width agent)                      ; => 1710
        (ua:vendor agent)                            ; => "Apple Computer, Inc."
        (ua:field agent '(:connection :effective-type))))
```

### Drawing many

Building a pool walks the whole dataset, so build it once and reuse it:

```lisp
(let ((pool (ua:make-pool '(:device-category :mobile))))
  (loop repeat 1000 collect (ua:user-agent-string (ua:random-user-agent pool))))
```

`randomize` redraws in place and `next-user-agent` returns a fresh agent, both
from the pool the agent already belongs to:

```lisp
(let ((agent (ua:make-user-agent (ua:regex "Android"))))
  (ua:randomize agent)          ; same object, new record, still Android
  (ua:next-user-agent agent))   ; new object, same pool
```

### The most common user agents

```lisp
(ua:top 10)                                ; ten heaviest overall
(ua:top 10 '(:device-category :mobile))    ; ten heaviest mobile ones
```

## Filters

A filter is compiled into a predicate applied to a record — or, when a filter
descends into a field, to that field's value.

| Filter | Meaning |
| --- | --- |
| `nil` or `t` | Matches anything |
| a function | Called with the value; its return value is the answer |
| `(ua:regex "...")` | Partial regex match, like JavaScript's `RegExp.test` |
| a string | `string=`, against the record's `:user-agent` when applied to a whole record |
| a keyword | As a string, but compared case-insensitively |
| a number | Numerically `=` |
| `(:key filter :key filter ...)` | Every named field must match |
| `(filter filter ...)` | Every filter must match |

A list is read as a field plist when its first element is a keyword, and as a
conjunction of filters otherwise. `ua:all-of`, `ua:any-of` and `ua:none-of`
spell a combination out explicitly when that inference is not what you want.

```lisp
;; Field constraints, including nested ones.
(ua:make-pool '(:platform "Win32"))
(ua:make-pool '(:device-category :tablet))
(ua:make-pool '(:connection (:effective-type "4g")))

;; A regex against the user agent string, or against one field.
(ua:make-pool (ua:regex "Chrome/1[45][0-9]"))
(ua:make-pool (list :platform (ua:regex "^Linux")))

;; Conjunction, disjunction, negation.
(ua:make-pool (list (ua:regex "Firefox") '(:device-category :desktop)))
(ua:make-pool (ua:any-of '(:device-category :mobile) '(:device-category :tablet)))
(ua:make-pool (ua:none-of '(:device-category :mobile)))

;; Anything else you can express as a predicate.
(ua:make-pool (lambda (record)
                (and (getf record :oscpu)
                     (> (getf record :viewport-height) 900))))
```

A filter that matches nothing signals `ua:no-matching-user-agents`, a subtype of
`ua:user-agents-error`:

```lisp
(handler-case (ua:make-user-agent '(:platform "Commodore 64"))
  (ua:no-matching-user-agents (c)
    (ua:no-matching-user-agents-filter c)))
;=> (:PLATFORM "Commodore 64")
```

## Records

Records are plists with kebab-case keyword keys: upstream's `screenHeight`
becomes `:screen-height`, `userAgent` becomes `:user-agent`, and JSON `null`
becomes `nil`. Nested objects such as `connection` are nested plists.

```lisp
(ua:user-agent-data (ua:make-user-agent))
;=> (:APP-NAME "Netscape" :CONNECTION (:DOWNLINK 10 :EFFECTIVE-TYPE "4g" :RTT 0)
;    :LANGUAGE "en-US" :PLATFORM "MacIntel" :PLUGINS-LENGTH 5 :SCREEN-HEIGHT 1107
;    :SCREEN-WIDTH 1710 :USER-AGENT "Mozilla/5.0 ..." :VENDOR "Apple Computer, Inc."
;    :VIEWPORT-HEIGHT 969 :VIEWPORT-WIDTH 1710 :WEIGHT 0.0002... :DEVICE-CATEGORY "desktop")
```

`ua:field` reads a key or a nested path, with an optional default; named
accessors exist for the common fields (`ua:platform`, `ua:device-category`,
`ua:screen-width`, `ua:vendor`, `ua:weight`, and so on).

```lisp
(ua:field agent :platform)
(ua:field agent '(:connection :effective-type))
(ua:field agent :oscpu :unknown)
```

Data handed back by `ua:user-agent-data`, `ua:pool-entries` and `ua:top` is
always a fresh copy, so you may modify it freely. `ua:all-user-agents` returns
the shared dataset and should be treated as read-only.

## Versioning

**Every change to the upstream dataset produces a new version of this port.**

`data/user-agents.json.gz` is a verbatim copy of upstream's
`src/user-agents.json.gz`, and its SHA-256 is what decides whether a release
happens. `scripts/update-data.sh` downloads the current upstream file and
compares hashes:

* **Unchanged** — nothing is written and the version stays where it is.
* **Changed** — the new file is parsed and sanity-checked, then vendored; the
  patch component of the version is incremented; `version.sexp`,
  `src/version.lisp` and `data/upstream.sexp` are regenerated; and a `CHANGELOG.md`
  entry is added.

```sh
./scripts/update-data.sh              # check and, if needed, cut a release
./scripts/update-data.sh --commit --tag
```

`.github/workflows/update-data.yml` runs this daily, runs the test suite against
the new dataset before accepting it, and pushes the commit and a `vX.Y.Z` tag.
The major and minor components are the API version and are maintained by hand.

The provenance of the vendored data is readable at runtime, and the test suite
asserts that it stays in sync with the file actually shipped:

```lisp
(ua:version)             ;=> "1.0.0"
ua:*upstream-version*    ;=> "2.1.157"    (the npm version it came from)
ua:*data-record-count*   ;=> 10000
ua:*data-retrieved*      ;=> "2026-08-19"
ua:*data-sha256*         ;=> "5f282ed647bce156..."
```

To try a dataset without vendoring it, point `ua:*data-file*` at it:

```lisp
(ua:reload-data #p"/tmp/user-agents.json.gz")
```

## Tests

```sh
sbcl --noinform --non-interactive --eval '(asdf:test-system :user-agents)'
```

## Differences from the JavaScript original

The behaviour — the dataset, the weighting, the filter semantics — is the same.
The interface is Lisp rather than a transliteration of the JavaScript one:

* Upstream returns a `Proxy` whose properties are the record's fields and which
  is callable to redraw. Here a `user-agent` is a struct; use the named
  accessors or `ua:field` for fields, and `ua:randomize` / `ua:next-user-agent`
  to redraw.
* Upstream rebuilds the weight distribution inside every constructor call. Here
  that work is a `pool`, which you can build once and sample repeatedly.
* Upstream's `UserAgent.random()` returns `null` when nothing matches; this port
  signals `ua:no-matching-user-agents` instead.
* Arrays of filters mean "all of these" in both; this port adds `ua:any-of` and
  `ua:none-of`, and accepts keywords as case-insensitive string values.
* Field names are kebab-case keywords rather than camelCase strings.

## Credits

This library is a port, and the interesting parts are not mine. The dataset, the
work of collecting and weighting real-world user agents, and the design this
port follows are all from
[intoli/user-agents](https://github.com/intoli/user-agents) by
[Intoli, LLC](https://intoli.com) — including the weighting scheme that makes a
random draw resemble real traffic rather than a uniform sample of browsers, and
the filter semantics reproduced here.

`data/user-agents.json.gz` is a verbatim copy of the file that project generates
and publishes, refreshed directly from their repository; see
[Versioning](#versioning). If you find this library useful, the credit belongs
upstream.

This port is not affiliated with or endorsed by Intoli.

## License

BSD-2-Clause; see `LICENSE`. The vendored dataset comes from
[intoli/user-agents](https://github.com/intoli/user-agents), also BSD-2-Clause,
whose copyright notice is retained in `LICENSE.upstream` as that license
requires.
