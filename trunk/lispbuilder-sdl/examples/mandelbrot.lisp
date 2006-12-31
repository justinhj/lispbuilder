;;;; Demonstration/Test of using SDL (Simple Media Layer) library
;;;; using CFFI for foreign function interfacing...
;;;; (C)2006 Frank Busse
;;;; Modifications Justin Heyes-Jones (more realtime, allows zoom in)
;;;; see COPYING for license
;;;; From "http://www.frank-buss.de/lisp/canvas.html"

(in-package #:sdl-examples) 

(defvar *x0* 0.2)
(defvar *y0* 0.5)
(defvar *x1* 0.4)
(defvar *y1* 0.7)
(defvar *width* 300)
(defvar *height* 300)
(defvar *zoom-ratio* 0.5)

(defun clear-screen()
  "clear the whole screen"
  (sdl::clear-display (sdl::color)))

(defun update-mandelbrot-draw (width height sx sy sw sh x0 y0 x1 y1)
  "draw mandelbrot from screen position sx,sy to the extent by sw,sh (width height)"
  (sdl::with-surface (surf sdl::*default-display*)
    (sdl::with-color (col (sdl::color))
      (loop for y from sy below (+ sy sh) do
	   (loop for x from sx below (+ sx sw) do
		(loop with a = (complex (float (+ (* (/ (- x1 x0) width) x) x0))
					(float (+ (* (/ (- y1 y0) height) y) y0)))
		   for z = a then (+ (* z z) a)
		   while (< (abs z) 2)
		   for c from 60 above 0
		   finally (progn
			     (setf col.r (mod (* 13 c) 256)
				   col.g (mod (* 7 c) 256)
				   col.b (mod (* 2 c) 256))
			     (sdl:write-pixel x y col))))))))

(defun mandelbrot 
    (&optional (width *width*) (height *height*) (x0 *x0*) (y0 *y0*) (x1 *x1*) (y1 *y1*))
  "main program to draw navigate mandelbrot set"
  (let ((cx 0) (cy 0) (step 10))
    (sdl::with-init ()
      (sdl::window width height :title-caption "Mandelbrot" :icon-caption "Mandelbrot")
      (setf (sdl-base::frame-rate) 0)
      (sdl::with-events ()
	(:idle ()
	       (if (>= cx width)
		   (and (setf cx 0) (incf cy step)))
	       (if (< cy height)
		   (update-mandelbrot-draw width height cx cy step step x0 y0 x1 y1))
	       (incf cx step)
	       (sdl::update-display))
	(:quit-event () t)
	(:mouse-button-down-event (:x x :y y)
					; set the new center point
				  (let* ((old-width (- x1 x0))
					 (old-height (- y1 y0))
					 (x-ratio (/ (float x) width))
					 (y-ratio (/ (float y) height))
					 (new-width (* old-width *zoom-ratio*))
					 (new-height (* old-height *zoom-ratio*))
					 (new-mid-x (+ x0 (* x-ratio old-width)))
					 (new-mid-y (+ y0 (* y-ratio old-height))))
				    (setf x0 
					  (- new-mid-x (/ new-width 2.0)))
				    (setf y0
					  (- new-mid-y (/ new-height 2.0)))
				    (setf x1
					  (+ x0 new-width))
				    (setf y1
					  (+ y0 new-height)))
				  (setf cx 0)
				  (setf cy 0)
				  (clear-screen))
	(:key-down-event (:key key)
			 (if (sdl-base::key= key :SDL-KEY-ESCAPE)
			     (sdl-base::push-quit-event)))
	(:video-expose-event () (sdl::update-display))))))