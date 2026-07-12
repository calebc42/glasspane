;;; glasspane-vulpea.el --- Vulpea integration for Glasspane -*- lexical-binding: t; -*-

(require 'vulpea-db-extract nil t)

(defun glasspane-vulpea--extract-mobile (ctx note-data)
  "Extract Tasker/Mobile context properties from a note."
  (let* ((props (plist-get note-data :properties))
         (location (cdr (assoc "LOCATION" props)))
         (wifi (cdr (assoc "WIFI_SSID" props)))
         (battery (cdr (assoc "BATTERY_LEVEL" props)))
         (activity (cdr (assoc "ACTIVITY" props)))
         (bluetooth (cdr (assoc "BLUETOOTH_DEVICES" props))))
    (if (or location wifi battery activity bluetooth)
        (plist-put note-data :glasspane-mobile
                   (list :note-id (plist-get note-data :id)
                         :location location
                         :wifi wifi
                         :battery (when battery (string-to-number battery))
                         :activity activity
                         :bluetooth bluetooth))
      note-data)))

(defun glasspane-vulpea--batch-insert-mobile (db tx all-note-data)
  "Insert mobile context data into SQLite."
  (let (rows)
    (dolist (data all-note-data)
      (when-let ((mobile (plist-get data :glasspane-mobile)))
        (push (vector (plist-get mobile :note-id)
                      (plist-get mobile :location)
                      (plist-get mobile :wifi)
                      (plist-get mobile :battery)
                      (plist-get mobile :activity)
                      (plist-get mobile :bluetooth))
              rows)))
    (when rows
      (emacsql db [:insert :into glasspane_mobile :values $v1] (vconcat rows)))))

(defun glasspane-vulpea--delete-mobile (db tx file-path)
  "Delete mobile context data for FILE-PATH."
  (emacsql db [:delete :from glasspane_mobile
               :where (in note-id [:select id :from notes
                                   :where (= path $s1)])]
           file-path))

(when (fboundp 'vulpea-db-register-extractor)
  (vulpea-db-register-extractor
   (make-vulpea-extractor
    :name 'glasspane-mobile
    :version 1
    :priority 90
    :schema '((glasspane_mobile (note-id text :not-null :primary-key)
                                (location text)
                                (wifi text)
                                (battery integer)
                                (activity text)
                                (bluetooth text)))
    :extract-fn #'glasspane-vulpea--extract-mobile
    :batch-insert-fn #'glasspane-vulpea--batch-insert-mobile
    :delete-fn #'glasspane-vulpea--delete-mobile)))

(provide 'glasspane-vulpea)
;;; glasspane-vulpea.el ends here
