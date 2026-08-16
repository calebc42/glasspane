;;; >>> Jetpacs managed: Android Emacs HOME >>>
;; Termux-shared mode redirects Android Emacs before normal init lookup so
;; Emacs and Termux use one private HOME and one private ~/.emacs.d.
(setenv "HOME" "/data/data/com.termux/files/home")
(setq default-directory "/data/data/com.termux/files/home/")
(setq user-emacs-directory "/data/data/com.termux/files/home/.emacs.d/")
(setq abbreviated-home-dir nil)

;; The exact Termux PATH snippet exposed by the Companion's Copy button.
(setenv "PATH" (format "%s:%s" "/data/data/com.termux/files/usr/bin"
		       (getenv "PATH")))
(push "/data/data/com.termux/files/usr/bin" exec-path)
;;; <<< Jetpacs managed: Android Emacs HOME <<<
