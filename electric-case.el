;;; electric-case.el --- Electric case conversion.

;; Copyright (C) 2013 zk_phi

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

;; Version: 1.1.1
;; Author: zk_phi
;; URL: http://hins11.yu-yake.com/

;;; Commentary:

;; 1. Usage

;; For example, to try electric-case-mode in java-mode, put following expression
;; into your init file.
;;
;;   (add-hook 'java-mode-hook electric-case-java-init)
;;
;; Now, when you type following expression as usual in java-mode,
;;
;;   public class test-class{
;;       public void test-method(void){
;;
;; electric-case will automatically convert it into :
;;
;;   public class TestClass{
;;       public void testMethod(void){
;;
;; "electric-case-java-init" and "electric-case-c-init" is prepared by default.
;; Field reference, and method calls are not converted by default. But you may
;; enable by evaluating code below:
;;
;;   (setq electric-case-cc-convert-calls t)
;;
;; Now expression below
;;
;;   object-name.method-name();
;;
;; is comverted into
;;
;;   objectName.methodName();
;;
;; To use UpperCamelCase, type something like:
;;
;;   -long-name-class-example.static-method();
;;
;; then it is comverted into
;;
;;   LongNameClassExample.staticMethod();

;; 2. Configuration

;; There are three important buffer-local variables. To add settings for other
;; languages, set these variables.

;; * electric-case-mode
;;
;;   When non-nil, electric-case-mode-map is activated

;; * electric-case-mode-map
;;
;;   Bind keys that you want use as electric-case trigger. When triggered, 2 symbols
;;   just before the cursor will be converted.
;;
;;     (define-key electric-case-mode-map (kbd "SPC") 'electric-case-trigger)
;;     (define-key electric-case-mode-map (kbd "(") 'electric-case-trigger)
;;     (define-key electric-case-mode-map (kbd ";") 'electric-case-trigger)
;;     (define-key electric-case-mode-map (kbd ",") 'electric-case-trigger)
;;
;;   Note that "electric-case-trigger" command will also call original command after
;;   conversion. For example, even if (kbd "SPC") is bound to electric-case trigger,
;;   still whitespace is inserted with (kbd "SPC").

;; * electric-case-criteria
;;
;;   Set a function that defines which case to convert the symbol into. The function
;;   will be given 3 arguments: the beginning and end point of the symbol that is going
;;   to be converted, and number of symbols between this symbol and the cursor. The
;;   function must return one of 'camel, 'ucamel, 'snake, 'usnake, and nil. When the
;;   return value is nil, the symbol will not be converted.
;;
;;   Here is an example:
;;
;;     (setq electric-case-criteria
;;           (lambda (b e n)
;;             (let ((proper (text-properties-at b)))
;;               (cond ((member 'font-lock-function-name-face proper) 'snake)
;;                     ((member 'font-lock-variable-name-face proper)
;;                      (if (member '(cpp-macro) (c-guess-basic-syntax))
;;                          'usnake 'snake))
;;                     (t nil)))))
;;
;;   with criteria above, function declarations and variable declarations are converted
;;   into snake_case. Macro declarations are converted into UP_SNAKE_CASE.
;;
;;     int a-variable;  =>  int a_variable;
;;
;;     #define macro_name => #define MACRO_NAME
;;
;;   But other expressions are not converted, even if that contain "-".
;;
;;     a = b-c;  =>  a = b-c; (NOT "a = bC;")

;;; Change Log:

;; 1.0.0 first released
;; 1.1.0 added electric-case-cc-convert-calls

;;; Code:

;; * constants

(defconst electric-case-version "1.1.1")

;; * variables

(defvar electric-case-mode nil)
(make-variable-buffer-local 'electric-case-mode)

(defvar electric-case-criteria (lambda (b e n) 'camel))
(make-variable-buffer-local 'electric-case-criteria)

(defvar electric-case-mode-map (make-sparse-keymap))
(make-variable-buffer-local 'electric-case-mode-map)

(when (not (assq 'electric-case-mode minor-mode-alist))
  (add-to-list
   'minor-mode-alist
   '(electric-case-mode " Case")))

(when (not (assq 'electric-case-mode-map minor-mode-map-alist))
  (add-to-list
   'minor-mode-map-alist
   (cons 'electric-case-mode electric-case-mode-map)))

(defun electric-case-mode (&optional arg)
  "Toggle electric-case-mode"
  (interactive)
  (setq electric-case-mode (cond ((null arg) (not electric-case-mode))
                                 ((> arg 0) t)
                                 (t nil))))

;; * utilities

(defmacro electric-case-save-excursion (&rest sexps)
  `(progn
     (insert "")
     (backward-char)
     ,@sexps
     (search-forward "")
     (delete-char -1)))

(defun electric-case-backward-symbol (&optional n)
  (interactive)
  (when (null n) (setq n 1))
  (while (>= (setq n (1- n)) 0)
    (backward-word)
    (goto-char (+ (point) (skip-chars-backward "[:alnum:]-")))))

(defun electric-case-forward-symbol (&optional n)
  (interactive)
  (when (null n) (setq n 1))
  (while (>= (setq n (1- n)) 0)
    (forward-word)
    (goto-char (+ (point) (skip-chars-forward "[:alnum:]-")))))

;; * functions, commands

(defun electric-case-convert-previous (n)
  (electric-case-save-excursion
   (if (< (point)
          (progn (electric-case-backward-symbol n)
                 (electric-case-forward-symbol) (point)))
       ;; no symbols to convert found before cursor
       ;; => backward-word, in preparation of e-c-save-excursion
       (backward-word)
     ;; convert the symbol before cursor, and replace
     (let* ((beg (save-excursion (electric-case-backward-symbol) (point)))
            (end (point))
            (type (apply electric-case-criteria (list beg end (1- n))))
            (wlst (split-string (buffer-substring-no-properties beg end) "-"))
            (convstr (cond ((eq type 'ucamel)
                            (mapconcat '(lambda (w) (upcase-initials w)) wlst ""))
                           ((eq type 'camel)
                            (concat
                             (car wlst)
                             (mapconcat '(lambda (w) (upcase-initials w)) (cdr wlst) "")))
                           ((eq type 'usnake)
                            (mapconcat '(lambda (w) (upcase w)) wlst "_"))
                           ((eq type 'snake)
                            (mapconcat 'identity wlst "_"))
                           (t
                            (mapconcat 'identity wlst "-")))))
       (delete-region beg end)
       (goto-char beg)
       (insert convstr)))))

(defun electric-case-trigger ()
  (interactive)
  (electric-case-convert-previous 2)
  (electric-case-convert-previous 1)
  ;; call original command
  (when (interactive-p)
    (let ((electric-case-mode nil))
      (call-interactively (key-binding (this-single-command-keys))))))

;; * cc-mode example

(defvar electric-case-cc-convert-calls nil)

(defun electric-case-letbuf (beg end str &rest sexps)
  (let ((ret (point)) (prev (buffer-substring beg end)) e val)
    (kill-region beg end)
    (goto-char beg)
    (insert str)
    (setq e (point))
    (goto-char (+ ret (- (length str) (length prev))))
    (setq val (eval (cons 'progn sexps)))
    (kill-region beg e)
    (goto-char beg)
    (insert prev)
    (goto-char ret)
    val))

  (defun electric-case-cc-semi ()
    (interactive)
    (insert ";")
    (backward-char)
    (electric-case-trigger)
    (forward-char)
    (delete-char -1)
    ;; call original command
    (when (interactive-p)
      (let ((electric-case-mode nil))
        (call-interactively (key-binding (this-single-command-keys))))))

(defun electric-case-c-init ()

  (electric-case-mode 1)

  (setq electric-case-criteria
        (lambda (b e n)
          (let ((proper (electric-case-letbuf
                           b e
                           (replace-regexp-in-string "-" "" (buffer-substring b e))
                           '(font-lock-fontify-block)
                           `(text-properties-at ,b)))
                (key (key-description (this-single-command-keys))))
            (cond ((member 'font-lock-function-name-face proper) 'snake)
                  ((member 'font-lock-type-face proper) 'snake)
                  ((member 'font-lock-variable-name-face proper)
                   (if (member '(cpp-macro) (c-guess-basic-syntax))
                       'usnake 'snake))
                  ((and electric-case-cc-convert-calls (= n 0)
                        (string= key "("))
                   'snake)
                  (t nil)))))

  (define-key electric-case-mode-map (kbd "SPC") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd "(") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd ";") 'electric-case-cc-semi)
  (define-key electric-case-mode-map (kbd ",") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd "=") 'electric-case-trigger)
  )

(defconst electric-case-java-primitives
  '("boolean" "char" "byte" "short" "int" "long" "float" "double" "void"))

(defun electric-case-java-init ()

  (electric-case-mode 1)

  (setq electric-case-criteria
        (lambda (b e n)
          (when (not (member (buffer-substring b e) electric-case-java-primitives))
            (let ((proper (electric-case-letbuf
                           b e
                           (replace-regexp-in-string "-" "" (buffer-substring b e))
                           '(font-lock-fontify-block)
                           `(text-properties-at ,b))) ; text properties at b
                  (key (key-description (this-single-command-keys))) ; this command keys
                  (pred (if (> (1- b) 0) (buffer-substring (1- b) b) "")) ; char before b
                  )
              (message "pred : %s" pred)
              (cond ((member 'font-lock-function-name-face proper) 'camel)
                    ((member 'font-lock-variable-name-face proper) 'camel)
                    ((member 'font-lock-type-face proper)
                     (if (not (member (buffer-substring b e) electric-case-java-primitives))
                         'ucamel))
                    ((and electric-case-cc-convert-calls (= n 0))
                     (if (or (string= key ".")
                             (string= key "(")
                             (string= pred "."))
                         'camel))
                    (t nil))))))

  (define-key electric-case-mode-map (kbd "SPC") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd "(") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd ";") 'electric-case-cc-semi)
  (define-key electric-case-mode-map (kbd ",") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd "{") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd "=") 'electric-case-trigger)
  (define-key electric-case-mode-map (kbd ".") 'electric-case-trigger)
  )

;; * provide

(provide 'electric-case)

;;; electric-case.el ends here
