;;; >>> Jetpacs managed: Android Emacs HOME >>>
;; Local Emacs keeps the private HOME Android assigned it. The user's Vault
;; may be /sdcard, this private home, or Termux home; it never relocates
;; .emacs.d because Vault and Unix HOME are independent choices.

;; The exact Termux PATH snippet exposed by the Companion's Copy button.
(setenv "PATH" (format "%s:%s" "/data/data/com.termux/files/usr/bin"
		       (getenv "PATH")))
(push "/data/data/com.termux/files/usr/bin" exec-path)
;;; <<< Jetpacs managed: Android Emacs HOME <<<
