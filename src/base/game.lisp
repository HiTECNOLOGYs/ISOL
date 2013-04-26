(in-package #:isol)

(defstruct Game
  map
  (player (make-instance 'player :location (list 1 1)))
  (creatures (make-hash-table)))

(defun game-step (game)
  (clear-screen)
  (print-map (game-map game))
  (write (game-player game)
         :stream :game-window)
  (redraw-screen)
  (process-key (wait-for-key)
               (game-player game)
               (game-map game)))


(defparameter *game* (make-game))

(define-condition exit-game () ())

(define-key-processor #\q ()
  (declare (ignore player map))
  (error 'exit-game))

(defun run-game ()
  "Runs game."
  (setf (game-map *game*)
        (load-map-from-file (make-pathname :directory '(:relative "res")
                                           :name "test-map"
                                           :type "isol")))
  (push-object (game-map *game*) 3 2 (get-object-instance-from-symbol :gun))
  (with-screen (:noecho :nocursor)
    (catch 'end-game
      (handler-case (loop (game-step *game*)
                       (sleep 1/100))
        (exit-game ()
          (throw 'end-game (values)))
        (sb-sys:interactive-interrupt ()
          (throw 'end-game (values)))))))
         
