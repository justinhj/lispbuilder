
(in-package #:sdl-examples)

;; Explosion textures from;
;; http://www.positech.co.uk/content/explosion/explosiongenerator.html

(defun explosion ()
  (sdl:with-init ()
    (sdl:window 200 100 :title-caption "Explosion" :icon-caption "Explosion")
    (setf (sdl:frame-rate) 25)
    
    (let* ((sprite-sheet (sdl:load-image (merge-pathnames "ani2.bmp" sdl:*default-asset-path*)))
           ;; Create the list of cells
           ;; Each 'cell' is the x/y width/height of an image in the sprite sheet
           (sprite-cells (loop for y from 0 to 192 by 64
                               append (loop for x from 0 to 192 by 64
                                        collect (list x y 64 64))))
           (current 0))

      ;; Set the the cells for the sprite-sheet
      (setf (sdl:cells sprite-sheet) sprite-cells)
      
      (sdl:with-events ()
        (:quit-event () t)
        (:key-down-event ()
         (when (sdl:key-down-p :sdl-key-escape)
           (sdl:push-quit-event)))
        (:video-expose-event () (sdl:update-display))
        (:idle ()
         (sdl:clear-display sdl:*black*)
         ;; Draw sprite in the middle of the window
         (sdl:draw-surface-at-* sprite-sheet (- 100 32) 10 :cell current)
         ;; Loop over each cell
         (when (>= (incf current) (length sprite-cells))
           (setf current 0))
         (sdl:update-display))))))
