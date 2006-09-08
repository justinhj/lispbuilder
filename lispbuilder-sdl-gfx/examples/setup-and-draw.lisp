;;;;; Converted from the "Setup and Draw" Processing example at:
;;;;; "http://www.processing.org/learning/examples/setupdraw.html"
;;;;; (C)2006 Luke J Crook

(in-package #:sdl-gfx-examples) 

(defun setup-and-draw ()
  (let ((width 200) (height 200)
	(y 100))
    (sdl:with-init ()
      (sdl:set-framerate 30)
      (sdl:with-display (width height :title-caption "Setup and Draw, from Processing.org")
	(sdl:clear-display :color #(0 0 0))
	(sdl:with-events ()
	  (:quit () t)
	  (:idle ()
		 (sdl:clear-display :color #(0 0 0))
		 (decf y 1)
		 (when (< y 0)
		   (setf y height))
		 (sdl-gfx:draw-hline 0 width y :color #(255 255 255))
		 (sdl:update-display)))))))
