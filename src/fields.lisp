;;;; fields.lisp --- Convenience accessors for user agent record fields.

(in-package #:user-agents)

(defun field (object key &optional default)
  "Look up KEY in OBJECT, a USER-AGENT or a raw record plist.

KEY is a keyword, or a list of keywords naming a nested path:

  (field ua :platform)
  (field ua '(:connection :effective-type))

DEFAULT is returned when the path is absent.  Note that a field present but set
to JSON null reads as NIL, not as DEFAULT."
  (let ((value (if (user-agent-p object) (user-agent-data object) object)))
    (dolist (step (if (listp key) key (list key)) value)
      (multiple-value-bind (subvalue presentp) (getf-present value step)
        (unless presentp
          (return default))
        (setf value subvalue)))))

(macrolet ((define-field-accessors (&rest names)
             `(progn
                ,@(mapcar
                   (lambda (name)
                     `(defun ,name (object)
                        ,(format nil "The ~(~a~) field of OBJECT, a user agent or a record plist."
                                 name)
                        (field object ,(intern (symbol-name name) :keyword))))
                   names))))
  (define-field-accessors
    app-name connection device-category language oscpu platform plugins-length
    screen-height screen-width vendor viewport-height viewport-width weight))
