;; SDL (Simple Media Layer) library using CFFI for foreign function interfacing...
;; (C)2006 Justin Heyes-Jones <justinhj@gmail.com> and Luke Crook <luke@balooga.com>
;; Thanks to Frank Buss and Surendra Singh
;; see COPYING for license
;; This file contains some useful functions for using SDL from Common lisp
;; using sdl.lisp (the CFFI wrapper)

(in-package #:lispbuilder-sdl) 

;;;; Macros

;;; c

(defmacro check-bounds (min below &rest vars)
  (let (result)
    (loop for var in vars do
	  (push `(when (< ,var ,min) (setf ,var ,min)) result)
	  (push `(when (>= ,var ,below) (setf ,var (1- ,below))) result))
    (push 'progn result)
    result))

;;; w
(defmacro with-init (init-flags &body body)
  "Attempts to initialize the SDL subsystems using SDL_Init.
   Automatically shuts down the SDL subsystems using SDL_Quit upon normal application termination or
if any fatal error occurs within &body.
   init-flags can be any combination of SDL_INIT_TIMER, SDL_INIT_AUDIO, SDL_INIT_VIDEO, SDL_INIT_CDROM,
SDL_INIT_JOYSTICK, SDL_INIT_NOPARACHUTE, SDL_INIT_EVENTTHREAD or SDL_INIT_EVERYTHING."
  `(block nil
    (unwind-protect
	 (when (init-sdl :flags (list ,@init-flags))
	   ,@body)
      (SDL_Quit))))

;; cl-sdl "sdl-ext.lisp"
(defmacro with-locked-surface ((var &optional surface) &body body)
  `(let (,@(when surface `(,var ,surface)))
     (unwind-protect 
         (progn (when (must-lock-p ,var)
                  (lock-surface ,var))
                ,@body)
       (when (must-lock-p ,var)
         (unlock-surface ,var)))))

(defmacro with-must-locksurface (surface &body body)
  "WITH-MUST-LOCKSURFACE sets up a surface for directly accessing the pixels using SDL_LockSurface.
   WITH-MUST-LOCKSURFACE uses SDL_MUSTLOCK to first check if the surface should be locked.
   Within WITH-MUST-LOCKSURFACE you can write to and read from surface->pixels, using the pixel format 
stored in surface->format."
  (let ((surf (gensym)))
    `(let ((,surf ,surface))
      (block nil
	(when (sdl-must-lock ,surf)
	  (if (>= (SDL_LockSurface ,surf) 0)
	      (progn
		,@body)
	      (error "Cannot lock surface")))
	(when (sdl-must-lock ,surf)
	  (SDL_UnlockSurface ,surf))))))

;; cl-sdl "cl-sdl.lisp"
(defmacro with-possible-lock-and-update ((surface &key (check-lock-p t) (update-p nil) (template nil)) &body body)
  (let ((locked-p (gensym "LOCKED-P"))
        (exit (gensym "EXIT"))
	(result (gensym "RESULT")))
    `(let ((,locked-p nil)
	   (,result nil))
      (block ,exit
        (when ,check-lock-p
          (when (must-lock-p ,surface)
            (when (< (sdl:SDL_LockSurface ,surface)
                     0)
              (return-from ,exit (values)))
            (setf ,locked-p t)))
        (setf ,result (progn ,@body))
        (when ,locked-p
          (SDL_UnlockSurface ,surface))
        (when ,update-p
          (update-surface ,surface :template ,template))
	,result))))

(defmacro with-surface-lock(surface &body body)
  (let ((surf (gensym "SURF"))
	(result (gensym "RESULT")))
    `(let ((,surf ,surface)
	   (,result nil))
       (progn
	 (SDL_LockSurface ,surf)
	 (setf ,result (progn ,@body))
	 (SDL_UnlockSurface ,surf)
	 ,result))))

;; cl-sdl "cl-sdl.lisp"
#+nil
(defmacro with-vraster ((buffer surface) &body body)
  `(let ((,buffer (sdl:make-vraster ,surface)))
    (unwind-protect (progn ,@body)
      (sdl:free-vraster ,buffer))))

(defmacro with-display ((width height &key (flags SDL_SWSURFACE) (bpp 0)
			       (title-caption nil) (icon-caption nil)
			       (display '*display)) &body body)
  (let ((body-value (gensym "body-value")))
    `(let ((,body-value nil)
	   (,display (set-window ,width ,height :bpp ,bpp :flags ,flags
				 :title-caption ,title-caption :icon-caption ,icon-caption)))
      (if (is-valid-ptr ,display)
	  (setf ,body-value (progn
			      ,@body)))
      (if (is-valid-ptr ,display)
	  (SDL_FreeSurface ,display))
      ,body-value)))

(defmacro with-surface ((surface-ptr &key (surface-name '*surface-name)) &body body)
  (let ((body-value (gensym "body-value")))
    `(let ((,body-value nil)
	   (,surface-name ,surface-ptr))
      (when (is-valid-ptr ,surface-name)
	(setf ,body-value (progn
			    ,@body))
	(if (is-valid-ptr ,surface-name)
	    (SDL_FreeSurface ,surface-name)))
      ,body-value)))

;;;; Functions

;;; a

(defun blit-surface (src dst &key (src-rect nil) (dst-rect nil) (position nil) (free-src nil) update-p)
  "Blits the entire SRC SDL_Surface to the DST SDL_Surface using SDL_BlitSurface.
   use :src-rect SDL_Rect to blit only a portion of the SRC to the DST surface
   Use :dst-rect SDL_Rect to position the SRC on the DST surface."
  (if src-rect
      (if (= 2 (length src-rect))
	  (setf src-rect (vector (rect-x src-rect) (rect-y src-rect) (surf-w src) (surf-h src)))))
  (if dst-rect
      (if (= 2 (length dst-rect))
	  (setf dst-rect (vector (rect-x dst-rect) (rect-y dst-rect) (surf-w src) (surf-h src)))))
  (with-possible-lock-and-update (dst :check-lock-p nil :update-p update-p :template dst-rect)
    (sdl::UpperBlit src src-rect dst dst-rect))
  (if free-src
      (when (is-valid-ptr src)
	(SDL_FreeSurface src)))
  dst-rect)

;;; c

;; cl-sdl "util.lisp"
(defun clamp (v l u)
  (min (max v l) u))

(defun clear-colorkey (surface &key (accel nil))
  "Removes the key color from the given surface."
  (when (is-valid-ptr surface)
    (if accel
	(setf accel SDL_RLEACCEL)
	(setf accel 0))
    (SDL_SetColorKey surface accel 0)))

;; cl-sdl "cl-sdl.lisp"
(defun clear-screen (surface &rest args)
  (apply #'fill-surface surface (vector 0 0 0) args)
  surface)

(defun color (r g b &optional a)
  (if a
      (vector r g b a)
      (vector r g b)))

(defun color-r (color)
  (elt color 0))
(defun (setf color-r) (r-val color)
  (setf (elt color 0) r-val))

(defun color-g (color)
  (elt color 1))
(defun (setf color-g) (g-val color)
  (setf (elt color 1) g-val))

(defun color-b (color)
  (elt color 2))
(defun (setf color-b) (b-val color)
  (setf (elt color 2) b-val))

(defun color-a (color)
  (elt color 3))
(defun (setf color-a) (a-val color)
  (setf (elt color 3) a-val))

(defun convert-surface-to-display-format (surface &key key-color alpha-value (free-surface t))
  "converts a surface to display format and free's the source surface"
  "  :alpha t will convert the surface and add an alpha channel."
  "  :free nil will not free surface."
  " returns NIL if the surface cannot be converted."
  ;; LJC: Added support for converting to an alpha surface.
  ;; LJC: Freeing surface is now optional.
  (when (is-valid-ptr surface)
    (if key-color
	(set-colorkey surface key-color))
    (if alpha-value
	(set-alpha surface alpha-value))
    (let ((display-surface (if alpha-value
			       (SDL_DisplayFormatAlpha surface)
			       (SDL_DisplayFormat surface))))
      (if free-surface
	  (SDL_FreeSurface surface))
      (if (is-valid-ptr display-surface)
	  display-surface
	  nil))))

(defun copy-rectangle (rectangle)
  (copy-seq rectangle))

(defun copy-surface (surface &key key-color alpha-value (type :sw) accel)
  "create a surface compatible with the supplied surface"
  (create-surface (surf-w surface) (surf-h surface)
		  :surface surface
		  :key-color key-color
		  :alpha-value alpha-value
		  :type type
		  :accel accel))

(defun create-surface(width height &key (bpp 32) surface pixels pitch key-color alpha-value (type :sw) (accel nil))
  "create a surface compatible with the supplied :surface, if provided."
  (let ((surf nil) (flags nil) (bpp 32))
    (if key-color
	(push SDL_SRCCOLORKEY flags))
    (if alpha-value
	(push SDL_SRCALPHA flags))
    (if accel
	(push SDL_RLEACCEL flags))
    (case type
      (:sw (push SDL_SWSURFACE flags))
      (:hw (push SDL_HWSURFACE flags)))
    (if (is-valid-ptr surface)
	(with-foreign-slots ((BitsPerPixel Rmask Gmask Bmask Amask) (pixelformat surface) SDL_PixelFormat)
	  (setf surf (SDL_CreateRGBSurface (set-flags flags)
					   width height BitsPerPixel Rmask Gmask Bmask Amask)))
	(let ((Rmask 0) (Gmask 0) (Bmask 0) (Amask 0))
	  ;; Set masks according to endianess of machine
	  ;; Little-endian (X86)
	  #+(or PC386 little-endian)(setf rmask #x000000ff
					  gmask #x0000ff00
					  bmask #x00ff0000
					  amask #xff000000)
	  ;; Big-endian (Motorola)
	  #-(or PC386 little-endian)(setf rmask #xff000000
					  gmask #x00ff0000
					  bmask #x0000ff00
					  amask #x000000ff)
	  (if (and pixels pitch)
	      ;; Pixels not yet supported.
	      nil
	      (setf surf (SDL_CreateRGBSurface (set-flags flags) width height bpp Rmask Gmask Bmask Amask)))))
    (if key-color
	(set-colorkey surf key-color :accel accel))
    (if alpha-value
	(set-alpha surf alpha-value :accel accel))
    surf))

;;; d

;; cl-sdl "util.lisp"
(defun delta-clamp (v d l u)
  (let ((sum (+ v d)))
    (cond ((< sum l)
           (- d (- sum l)))
          ((> sum u)
           (- d (- sum u)))
          (t d))))

(defun display-cursor (toggle)
  (case toggle
    (nil (SDL_ShowCursor sdl_disable))
    (t (SDL_ShowCursor sdl_enable))))

(defun query-cursor ()
  (case (SDL_ShowCursor sdl_query)
    (sdl_disable nil)
    (sdl_enable t)))

(defun random-rect (bound-w bound-h)
  (let* ((x (random bound-w))
	 (y (random bound-h))
	 (w (random+1 (- bound-w x)))
	 (h (random+1 (- bound-h y))))
    (vector x y w h)))

(defun random-color (&optional alpha)
  (if alpha ;; alpha is either t, or a number then create r/g/b/a
      (vector (random 255) (random 255) (random 255) (if (numberp alpha)
							 alpha
							 (random 255)))
      (vector (random 255) (random 255) (random 255))))	; Or not, and create an r/g/b color

(defun draw-rect(surface_ptr rect color &key update-p clipping-p)
  "Given a surface pointer draw a rectangle with the specified x,y, width, height and color"
  (fill-surface surface_ptr color :template rect :update-p update-p :clipping-p clipping-p)
  rect)

(defun draw-rect-end-points(surface_ptr x1 y1 x2 y2 color &key update-p clipping-p)
  "Given a surface pointer draw a rectangle with the specified corner co-ordinates and color"
  (fill-surface surface_ptr color
		:template (rect-from-endpoints x1 y1 x2 y2)
		:update-p update-p
		:clipping-p clipping-p))

;; cl-sdl "cl-sdl.lisp"
#+nil
(defun fill-vraster (surface buffer r g b)
  (check-types r g b (unsigned-byte 8))
  (sdl:fill-vraster surface buffer r g b)
  (values))

(defun fill-surface (surface color &key (template nil) (update-p nil) (clipping-p))
  "fill the entire surface with the specified R G B A color.
   Use :template to specify the SDL_Rect to be used as the fill template.
   Use :update-p to call SDL_UpdateRect, using :template if provided. This allows for a 
    'dirty recs' screen update."
  (when clipping-p
    (let* ((x (rect-x template)) (y (rect-y template))
	   (w (rect-w template)) (h (rect-h template))
	   (x2 (+ x w)) (y2 (+ y h)))
      (check-bounds 0 (surf-w surface) x x2)
      (check-bounds 0 (surf-h surface) y y2)
      (setf w (- x2 x)
            h (- y2 y))
      (setf template (vector x y w h))))
  (with-possible-lock-and-update (surface :check-lock-p nil :update-p update-p :template template)
    (FillRect surface template (map-color surface color)))
  template)

;;; g

(defun get-clip-rect (surface rect)
  (cffi:with-foreign-object (r 'sdl_rect)
    (getcliprect surface r)
    (vector (cffi:foreign-slot-value r sdl_rect x)
	    (cffi:foreign-slot-value r sdl_rect y)
	    (cffi:foreign-slot-value r sdl_rect w)
	    (cffi:foreign-slot-value r sdl_rect h))))

(defun get-native-window ()
  (let ((wm-info (cffi:foreign-alloc 'sdl::SDL_SysWMinfo)))
      ;; Set the wm-info structure to the current SDL version.
      (sdl::sdl_version (cffi:foreign-slot-value wm-info 'sdl::SDL_SysWMinfo 'sdl::version))
      (sdl::SDL_GetWMInfo wm-info)
      ;; For Windows
      #+win32(cffi:foreign-slot-pointer wm-info 'sdl::SDL_SysWMinfo 'sdl::window)
      ;; For X
      #-win32(cffi:foreign-slot-pointer (cffi:foreign-slot-pointer (cffi:foreign-slot-pointer wm-info
											      'SDL_SysWMinfo
											      'sdl::info)
								   'sdl::SDL_SysWMinfo_info
								   'sdl::x11)
					'sdl::SDL_SysWMinfo_info_x11
					'sdl::window)))

(defun get-pixel(surface point &key (check-lock-p t))
  "Get the pixel at (x, y) as a Uint32 color value
NOTE: The surface must be locked before calling this.
Also NOTE: Have not tested 1,2,3 bpp surfaces, only 4 bpp"
  (with-possible-lock-and-update (surface :check-lock-p check-lock-p :update-p nil :template (rect-from-point point 1 1))
    (let* ((bpp (foreign-slot-value (pixelformat surface) 'SDL_PixelFormat 'BytesPerPixel))
	   (offset (+ (* (point-y point) (foreign-slot-value surface 'SDL_Surface 'Pitch))
		      (* (point-x point) bpp)))
	   (pixel-address (foreign-slot-value surface 'SDL_Surface 'Pixels)))
      (cffi:with-foreign-objects ((r :unsigned-char) (g :unsigned-char) (b :unsigned-char) (a :unsigned-char))
	(SDL_GetRGBA (cond
		       ((= bpp 1) 
			(mem-aref pixel-address :unsigned-char offset))
		       ((= bpp 2) 
			(mem-aref pixel-address :unsigned-short (/ offset 2)))
		       ((= bpp 3) 
					;	 (if (eq SDL_BYTEORDER SDL_BIG_ENDIAN) ; TODO
			(error "3 byte per pixel surfaces not supported yet"))
		       ((= bpp 4) 
			(mem-aref pixel-address :unsigned-int (/ offset 4))))
		     (pixelformat surface)
		     r g b a)
	(vector (mem-aref r :unsigned-char)
		(mem-aref g :unsigned-char)
		(mem-aref b :unsigned-char)
		(mem-aref a :unsigned-char))))))
    

#|

/*
 * Return the pixel value at (x, y)
 * NOTE: The surface must be locked before calling this!
 */
Uint32 getpixel(SDL_Surface *surface, int x, int y)
{
    int bpp = surface->format->BytesPerPixel;
    /* Here p is the address to the pixel we want to retrieve */
    Uint8 *p = (Uint8 *)surface->pixels + y * surface->pitch + x * bpp;

    switch(bpp) {
    case 1:
        return *p;

    case 2:
        return *(Uint16 *)p;

    case 3:
        if(SDL_BYTEORDER == SDL_BIG_ENDIAN)
            return p[0] << 16 | p[1] << 8 | p[2];
        else
            return p[0] | p[1] << 8 | p[2] << 16;

    case 4:
        return *(Uint32 *)p;

    default:
        return 0;       /* shouldn't happen, but avoids warnings */
    }
}

|#

(defun get-surface-rect (surface)
  "Returns a rectangle containing the surfaces width and height. X and Y are both set to 0."
  (vector 0 0 (surf-w surface) (surf-h surface)))

(defun get-video-info (&key (video-info (SDL_GetVideoInfo)) (info :video-mem))
  "Returns information about the video hardware.
  GET-VIDEO-INFO :video-info <pointer to a SDL_VIDEOINFO structure>
                 :info :hw_available | :wm_available |
                       :blit_hw | :blit_hw_cc | :blit_hw_a |
                       :blit_sw | :blit_sw_cc | :blit_sw_a |
                       :blit_fill |
                       :video_mem |
                       :pixelformat
  Usage: get-video-info should be called after sdl_init but before sdl_setvideomode.
         e.g (get-video-info :info :video_mem), or
             (get-video-info :video-info (sdl_getvideoinfo) :info :video_mem)
         Will return the amount video memory available."
  (if (is-valid-ptr video-info)
      (case info
	(:video-mem
	 (cffi:foreign-slot-value video-info 'sdl_videoinfo 'video_mem))
	(:pixelformat
	 (cffi:foreign-slot-value video-info 'sdl_videoinfo 'vfmt))
	(otherwise
	 (member info (cffi:foreign-slot-value video-info 'sdl_videoinfo 'flags))))
      nil))


;;; h
;;; i

(defun init-sdl (&key (flags SDL_INIT_VIDEO))
  (if (equal 0 (SDL_Init (set-flags flags)))
      t
      nil))

(defun is-key (key1 key2)
  "Returns t if the keypress 'key1' is equal to the specified 'key2'.
   (cffi:foreign-enum-value 'SDLKey key2)."
  (equal key1 (cffi:foreign-enum-value 'SDLKey key2)))

(defun is-modifier (mod key)
  "Returns t if the keypress modifier 'mod' is equal to the specified 'key'.
   (cffi:foreign-enum-value 'SDLMod key)."
  (equal mod (cffi:foreign-enum-value 'SDLMod key)))

(defun is-valid-ptr (pointer)
  "IS-VALID-PTR <CFFI pointer>
  Will return T if 'pointer' is a valid <CFFI pointer> and is non-null."
  (and (cffi:pointerp pointer) (not (cffi:null-pointer-p pointer))))


;;; j
;;; k
;;; l

(defun list-modes (flags)
  "Returns a LIST of rects  for each available screen dimension "
  "for the given format and video flags, sorted largest to smallest. "
  "Returns NIL if there are no dimensions available for a particular format, "
  "or T if any dimension is okay for the given format."
  (let ((modes nil)
        (listmodes (sdl::SDL_ListModes (cffi:null-pointer) (set-flags flags))))
    (cond
      ((cffi:null-pointer-p listmodes)
       nil)
      ((equal (cffi:pointer-address listmodes) 4294967295)
       t)
      (t
       (do ((i 0 (1+ i)))
	   ((cffi:null-pointer-p (cffi:mem-ref (cffi:mem-aref listmodes 'sdl:sdl_rect i) :pointer)) (reverse modes))
	 (let ((rect (cffi:mem-ref (cffi:mem-aref listmodes 'sdl:sdl_rect i) :pointer)))
	   (setf modes (cons (vector (cffi:foreign-slot-value rect 'sdl:sdl_rect 'sdl:w)
				     (cffi:foreign-slot-value rect 'sdl:sdl_rect 'sdl:h))
			     modes))))))))

(defun load-bmp(filename)
  "load in the supplied filename, must be a bmp file"
  (if (and (stringp filename) (probe-file filename)) ; LJC: Make sure filename is a string and the filename exists.
      (SDL_LoadBMP_RW (RWFromFile filename "rb") 1)
      nil))

;;; m

(defun map-color (surface color)
  (if (equal 3 (length color))
      (sdl:SDL_MapRGB (pixelformat surface)
		      (color-r color) (color-g color) (color-b color))
      (sdl:SDL_MapRGBA (pixelformat surface)
		       (color-r color) (color-g color) (color-b color) (color-a color))))

(defun moveby-rectangle (rectangle dx dy)
  "add dx and dy to the x and y positions of the rectangle." 
  (setf (rect-x rectangle) (+ (rect-x rectangle) dx)
	(rect-y rectangle) (+ (rect-y rectangle) dy))
  rectangle)

(defun moveto-rectangle (rectangle dx dy)
  "set the x and y position of the rectangle."
  (setf (rect-x rectangle) dx
	(rect-y rectangle) dy)
  rectangle)

;; cl-sdl "sdl-ext.lisp"
(defun must-lock-p (surface)
  (or (/= 0 (cffi:foreign-slot-value surface 'sdl_surface 'offset))
      (/= 0 (logand (cffi:foreign-slot-value surface 'sdl_surface 'flags)
		    (logior SDL_HWSURFACE
			    SDL_ASYNCBLIT
			    SDL_RLEACCEL)))))

;;; n

(defun new-event (&key (event-type 'SDL_Event))
  "Creates a new SDL_Event and sets the type to :event-type.
   If no type is specified, then an SDL_Event of type SDL_NOEVENT is returned.
   For example, to create a quit event use :event-type 'SDL_QuitEvent."
  (let ((event (cffi:foreign-alloc event-type)))
    (setf (cffi:foreign-slot-value event 'SDL_event 'type)
	  (case event-type
	    ('sdl_quitevent SDL_QUIT)
	    (otherwise SDL_NOEVENT)))
    event))

(defun rectangle (x y w h)
  "Creates a new rectangle."
  (vector x y w h))

;;; o
;;; p

(defun pixelformat (surface)
  "Returns the pixelformat of a surface."
  (cffi:foreign-slot-value surface 'sdl:SDL_Surface 'sdl:format))

(defun point-x (point)
  (elt point 0))
(defun (setf point-x) (x-val point)
  (setf (elt point 0) x-val))

(defun point-y (point)
  (elt point 1))
(defun (setf point-y) (y-val point)
  (setf (elt point 1) y-val))

(defun point (x y)
  (vector x y))

(defun pos-x (position)
  (elt position 0))
(defun (setf pos-x) (x-val position)
  (setf (elt position 0) x-val))

(defun pos-y (position)
  (elt position 1))
(defun (setf pos-y) (y-val position)
  (setf (elt position 1) y-val))

(defun push-quitevent ()
  "Pushes a new SDL_Event of type SDL_QUIT onto the event queue."
  (SDL_PushEvent (new-event :event-type 'sdl_quitevent)))

(defun draw-pixel (surface point color &key (check-lock-p t) (update-p nil) (clipping-p t))
  "Set the pixel at (x, y) to the given value "
  "NOTE: The surface must be locked before calling this."
  "Also NOTE: Have not tested 1,2,3 bpp surfaces, only 4 bpp"
  (let ((x (point-x point)) (y (point-y point)))
    (when clipping-p
      (check-bounds 0 (surf-w surface) x)
      (check-bounds 0 (surf-h surface) y))
    (with-possible-lock-and-update (surface :check-lock-p check-lock-p :update-p update-p
					    :template (vector x y 1 1))
      (let* ((format (foreign-slot-value surface 'SDL_Surface 'format))
	     (bpp (foreign-slot-value format 'SDL_PixelFormat 'BytesPerPixel))
	     (offset (+ (* y (foreign-slot-value surface 'SDL_Surface 'Pitch))
			(* x bpp)))
	     (pixel-address (foreign-slot-value surface 'SDL_Surface 'Pixels))
	     (pixel (map-color surface color)))
	(cond
	  ((= bpp 1) 
	   (setf (mem-aref pixel-address :unsigned-char offset) pixel))
	  ((= bpp 2) 
	   (setf (mem-aref pixel-address :unsigned-short (/ offset 2)) pixel))
	  ((= bpp 3) 
	   (if (eq SDL_BYTEORDER SDL_BIG_ENDIAN)
	       (progn
		 (setf (mem-aref pixel-address :char offset) (logand (ash pixel -16) #xff))
		 (setf (mem-aref pixel-address :char (1+ offset)) (logand (ash pixel -8) #xff))
		 (setf (mem-aref pixel-address :char (+ 2 offset)) (logand pixel #xff)))
	       (progn
		 (setf (mem-aref pixel-address :char offset) (logand pixel #xff))
		 (setf (mem-aref pixel-address :char (1+ offset)) (logand (ash pixel -8) #xff))
		 (setf (mem-aref pixel-address :char (+ 2 offset)) (logand (ash pixel -16) #xff)))))
	  ((= bpp 4) 
	   (setf (mem-aref pixel-address :unsigned-int (/ offset 4)) pixel)))))))



#|
Reference source
void putpixel(SDL_Surface *surface, int x, int y, Uint32 pixel)
{
    int bpp = surface->format->BytesPerPixel;
    /* Here p is the address to the pixel we want to set */
    Uint8 *p = (Uint8 *)surface->pixels + y * surface->pitch + x * bpp;

    switch(bpp) {
    case 1:
        *p = pixel;
        break;

    case 2:
        *(Uint16 *)p = pixel;
        break;

    case 3:
        if(SDL_BYTEORDER == SDL_BIG_ENDIAN) {
            p[0] = (pixel >> 16) & 0xff;
            p[1] = (pixel >> 8) & 0xff;
            p[2] = pixel & 0xff;
        } else {
            p[0] = pixel & 0xff;
            p[1] = (pixel >> 8) & 0xff;
            p[2] = (pixel >> 16) & 0xff;
        }
        break;

    case 4:
        *(Uint32 *)p = pixel;
        break;
    }
}
|#



;;; q
;;; r

(defun random+1 (rnd)
  (+ 1 (random rnd)))

(defun rect-x (rect)
  (elt rect 0))
(defun (setf rect-x) (x-val rect)
  (setf (elt rect 0) x-val))

(defun rect-y (rect)
  (elt rect 1))
(defun (setf rect-y) (y-val rect)
  (setf (elt rect 1) y-val))

(defun rect-w (rect)
  (elt rect 2))
(defun (setf rect-w) (w-val rect)
  (setf (elt rect 2) w-val))

(defun rect-h (rect)
  (elt rect 3))
(defun (setf rect-h) (h-val rect)
  (setf (elt rect 3) h-val))

(defun rect-x2 (rect)
  (+ (rect-x rect) (rect-w rect)))
(defun (setf rect-x2) (h-val rect)
  (setf (rect-w rect) (+ (rect-x rect) h-val)))

(defun rect-y2 (rect)
  (+ (rect-y rect) (rect-h rect)))
(defun (setf rect-y2) (h-val rect)
  (setf (rect-h rect) (+ (rect-y rect) h-val)))

(defun rect-from-point (point width height)
  (vector (point-x point) (point-y point) width height))

(defun rect-from-endpoints (x1 y1 x2 y2)
  (vector x1 y1 (1+ (abs (- x1 x2))) (1+ (abs (- y1 y2)))))

;;; s

(defun sdl-must-lock (surface)
  "Checks if a surface can be locked.
   Re-implementation of the SDL_MUSTLOCK macro.
   Returns
    T if the surface can be locked.
    NIL if the surface cannot be locked."
  (if (> 0 (cffi:foreign-slot-value surface 'SDL_Surface 'offset))
      t
      (if (not (eql 0 (logand 
		       (cffi:foreign-slot-value surface 'SDL_Surface 'flags)
		       (logior SDL_HWSURFACE SDL_ASYNCBLIT SDL_RLEACCEL))))
	  t
	  nil)))


(defun set-alpha (surface alpha-value &key (accel nil))
  "Sets the alpha value for the given surface."
  (when (is-valid-ptr surface)
    (if accel
	(setf accel SDL_RLEACCEL)
	(setf accel 0))
    (if (null alpha-value)
	(SDL_SetAlpha surface accel 0)
	(SDL_SetAlpha surface (logior SDL_SRCALPHA accel) (clamp alpha-value 0 255)))
    surface))

(defun set-colorkey (surface color &key (accel nil))
  "Sets the key color for the given surface. The key color is made transparent."
  (when (is-valid-ptr surface)
    (if (null color)
	(SDL_SetColorKey surface 0 0)
	(progn
	  (if accel
	      (setf accel SDL_RLEACCEL)
	      (setf accel 0))
	  (SDL_SetColorKey surface (logior SDL_SRCCOLORKEY accel) (map-color surface color))))
    surface))

(defun set-clip-rect (surface rect)
  (setcliprect surface rect))


(defun set-flags (&rest keyword-args)
  (if (listp (first keyword-args))
      (let ((keywords 
	     (mapcar #'(lambda (x)
			 (eval x))
		     (first keyword-args))))
	(apply #'logior keywords))
      (apply #'logior keyword-args)))

(defun set-screen (width height
		   &key (bpp 0) (flags '(SDL_HWSURFACE SDL_FULLSCREEN SDL_HWACCEL)) title-caption icon-caption)
  "Will attempt to create a full screen, hardware accelerated window using SDL_SetVideoMode.
   Overriding :flags will allow any type of window to be created.
   Returns
    a new SDL_Surface if successful.
    NIL if failed."
  (let ((surface (SDL_SetVideoMode width height bpp (set-flags flags))))
    (if (or title-caption icon-caption) 
	(WM_SetCaption title-caption icon-caption))
    (if (is-valid-ptr surface)
	surface
	nil)))

(defun set-window (width height &key (bpp 0) (flags SDL_SWSURFACE) title-caption icon-caption)
  "Will attempt to create a window using software surfaces using SDL_SetVideoMode.
   Overriding :flags will allow any type of window to be created.
   Returns
    a new SDL_Surface if successful.
    NIL if failed."
  (set-screen width height :bpp bpp :flags flags :title-caption title-caption :icon-caption icon-caption))

;; cl-sdl "sdl-ext.lisp"
;; (defun show-bmp (file surface x y)
;;   (let ((bmp nil))
;;     (unwind-protect
;;          (progn
;;            (setf bmp (sdl:load-bmp file))
;;            (when bmp
;;              (blit-surface bmp surface :dst-rect (vector x y))
;; 	     (update-surface surface :template (vector x y (surf-w bmp) (surf-h bmp)))
;; 	     ))
;;       (when (is-valid-ptr bmp)
;; 	(cffi:foreign-free bmp)))))

(defun surf-w (surface)
  "return the width of the SDL_surface."
  (cffi:foreign-slot-value surface 'SDL_Surface 'w))

(defun surf-h (surface)
  "return the height of the SDL_Surface." 
  (cffi:foreign-slot-value surface 'SDL_Surface 'h))

;;; t

(defun to-radian (degree)
  "converts degrees to radians."
  (* degree (/ PI 180)))

(defun to-degree (radian)
  "converts radians to degrees."
  (/ radian (/ PI 180)))


;;; u

;; cl-sdl "cl-sdl.lisp"
(defun update-screen (surface)
  (sdl_flip surface))

(defun update-surface (surface &key (template nil))
  "Updates the screen using the keyword co-ordinates in the Vector, :template.
   All co-ordinates default to 0, updating the entire screen."
  (if (is-valid-ptr surface)
      (if template
	  (SDL_UpdateRect surface 
			  (rect-x template)
			  (rect-y template)
			  (rect-w template)
			  (rect-h template))
	  (SDL_UpdateRect surface 0 0 0 0)))
  surface)

;;; v

(defun video-driver-name ()
  (let ((function-return-val nil)
	(string-return-val nil))
    (setf string-return-val (with-foreign-pointer-as-string (str 100 str-size)
			      (setf function-return-val (videodrivername str str-size))))
    (if (cffi:null-pointer-p function-return-val)
	nil
	string-return-val)))

;; cl-sdl "cl-sdl.lisp"
;; vraster -- used to fill arbitrary convex polygons.
;; A structure with 2 arrays, holding the top and bottom
;; pixel positions for each x position.  Filling draws
;; a series of vertical lines for each x position from
;; top to bottom.
#+nil
(defun vraster-line (buffer x1 y1 x2 y2 &key (clipping-p t))
  (check-types x1 y1 x2 y2 (unsigned-byte 16))
  (when clipping-p
    (let ((sw-1 (1- (sdl:vraster-length buffer)))
          (sh-1 (1- (sdl:vraster-surface-height buffer))))
      ;; for now
      (setf x1 (sdl:clamp x1 0 sw-1)
            x2 (sdl:clamp x2 0 sw-1)
            y1 (sdl:clamp y1 0 sh-1)
            y2 (sdl:clamp y2 0 sh-1))))
  (sdl:vraster-line buffer x1 y1 x2 y2)
  (values))

;;; w

(defun warp-mouse (point)
  (sdl_warpmouse (point-x point) (point-y point)))

;;; x
;;; y
;;; z


;;; Event Handling & Timing routine from here   -----------------------


(let ((timescale nil))
    (defun set-timescale (tscale)
        (setf timescale tscale))
    (defun get-timescale ()
        timescale))

(let ((ticks nil))
    (defun set-ticks (tcks)
        (setf ticks tcks))
    (defun get-ticks ()
        ticks))

(let ((worldtime 100))
    (defun set-worldtime (wtime)
        (setf worldtime wtime))
    (defun get-worldtime ()
        worldtime))

(defstruct fpsmanager
  (framecount 0 :type fixnum)
  (rate 30 :type fixnum)
  (rateticks (/ 1000.0 30.0) :type float)
  (lastticks 0 :type fixnum))

(let ((fpsmngr (make-fpsmanager)) (fps-upper-limit 200) (fps-lower-limit 1)
      (current-ticks 0) (target-ticks 0))
;  (declare (type fixnum fps-upper-limit fps-lower-limit current-ticks target-ticks))
  (defun init-framerate-manager()
    (setf fpsmngr (make-fpsmanager)))
  (defun set-framerate (rate)
    (if (> rate 0)
        (if (and (>= rate fps-lower-limit) (<= rate fps-upper-limit))
            (progn
              (setf (fpsmanager-framecount fpsmngr) 0)
              (setf (fpsmanager-rate fpsmngr) rate)
              (setf (fpsmanager-rateticks fpsmngr) (/ 1000.0 rate))
              t)
	    nil)
	(setf (fpsmanager-rate fpsmngr) rate)))
  (defun get-framerate ()
    (fpsmanager-rate fpsmngr))
  (defun framerate-delay ()
    (when (> (fpsmanager-rate fpsmngr) 0)
      (setf current-ticks (sdl_getticks))
      (incf (fpsmanager-framecount fpsmngr))
      (setf target-ticks (+ (fpsmanager-lastticks fpsmngr) 
			    (* (fpsmanager-framecount fpsmngr) (fpsmanager-rateticks fpsmngr))))
      (if (<= current-ticks target-ticks)
	  (sdl_delay (round (- target-ticks current-ticks)))
	  (progn
	    (setf (fpsmanager-framecount fpsmngr) 0)
	    (setf (fpsmanager-lastticks fpsmngr) (sdl_getticks)))))))

(defun expand-activeevent (sdl-event params forms)
  `((eql SDL_ACTIVEEVENT (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_ActiveEvent 'gain)
     (cffi:foreign-slot-value ,sdl-event 'SDL_ActiveEvent 'state))))

(defun expand-keydown (sdl-event params forms)
  `((eql SDL_KEYDOWN (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
		   ,@forms)
             
     (cffi:foreign-slot-value ,sdl-event 'SDL_KeyboardEvent 'state)

     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'scancode)
     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'sym)
     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'mod)
     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'unicode))))

(defun expand-keyup (sdl-event params forms)
  `((eql SDL_KEYUP (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)

     (cffi:foreign-slot-value ,sdl-event 'SDL_KeyboardEvent 'state)

     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'scancode)
     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'sym)
     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'mod)
     (cffi:foreign-slot-value (cffi:foreign-slot-pointer ,sdl-event 'sdl_keyboardevent 'keysym) 'SDL_keysym 'unicode))))

(defun expand-mousemotion (sdl-event params forms)
  `((eql SDL_MOUSEMOTION (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseMotionEvent 'state)

     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseMotionEvent 'x)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseMotionEvent 'y)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseMotionEvent 'xrel)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseMotionEvent 'yrel))))

(defun expand-mousebuttondown (sdl-event params forms)
  `((eql sdl_mousebuttondown (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)

     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'button)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'state)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'x)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'y))))

(defun expand-mousebuttonup (sdl-event params forms)
  `((eql sdl_mousebuttonup (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'button)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'state)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'x)
     (cffi:foreign-slot-value ,sdl-event 'SDL_MouseButtonEvent 'y))))

(defun expand-joyaxismotion (sdl-event params forms)
  `((eql SDL_JOYAXISMOTION (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyAxisEvent 'which)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyAxisEvent 'axis)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyAxisEvent 'value))))

(defun expand-joybuttondown (sdl-event params forms)
  `((eql SDL_JOYBUTTONDOWN (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyButtonEvent 'which)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyButtonEvent 'axis)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyButtonEvent 'value))))

(defun expand-joybuttonup (sdl-event params forms)
  `((eql SDL_JOYBUTTONUP (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyButtonEvent 'which)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyButtonEvent 'axis)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyButtonEvent 'value))))

(defun expand-joyhatmotion (sdl-event params forms)
  `((eql SDL_JOYHATMOTION (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyHatEvent 'which)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyHatEvent 'axis)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyHatEvent 'value))))

(defun expand-joyballmotion (sdl-event params forms)
  `((eql SDL_JOYBALLMOTION (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyBallEvent 'which)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyBallEvent 'ball)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyBallEvent 'xrel)
     (cffi:foreign-slot-value ,sdl-event 'SDL_JoyBallEvent 'yrel))))

(defun expand-videoresize (sdl-event params forms)
  `((eql SDL_VIDEORESIZE (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_ResizeEvent 'w)
     (cffi:foreign-slot-value ,sdl-event 'SDL_ResizeEvent 'h))))

(defun expand-videoexpose (sdl-event forms)
  `((eql SDL_VIDEOEXPOSE (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ()
                 ,@forms))))

(defun expand-syswmevent (sdl-event forms)
  `((eql SDL_SYSWMEVENT (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (funcall #'(lambda ()
                 ,@forms))))

(defun expand-quit (sdl-event forms quit)
  `((eql SDL_QUIT (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type))
    (setf ,quit (funcall #'(lambda ()
                             ,@forms)))))

(defun expand-userevent (sdl-event params forms)
  `((and (>= (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type)
	  SDL_MOUSEMOTION)
     (< (cffi:foreign-slot-value ,sdl-event 'sdl_event 'type)
      (- SDL_NUMEVENTS 1)))
    (funcall #'(lambda ,params
                 ,@forms)
     (cffi:foreign-slot-value ,sdl-event 'SDL_UserEvent 'type)
     (cffi:foreign-slot-value ,sdl-event 'SDL_UserEvent 'code)
     (cffi:foreign-slot-pointer ,sdl-event 'SDL_UserEvent 'data1)
     (cffi:foreign-slot-pointer ,sdl-event 'SDL_UserEvent 'data2))))

(defun expand-idle (forms)
  `(progn
     ,@forms))

(defmacro with-events (&body events)
  "(with-sdl-events
       (:activeevent (gain state)
		     t)
     (:keydown (state keysym)
	       t)
     (:keyup (state keysm)
	     t)
     (:mousemotion (state x y xrel yrel)
		   t)
     (:mousebuttondown (button state x y)
		       t)
     (:mousebuttonup (button state x y)
		     t)
     (:joyaxismotion (which axis value)
		     t)
     (:joybuttondown (which button state)
		     t)
     (:joybuttonup (which button state)
		   t)
     (:joyhatmotion (which hat value)
		    t)
     (:joyballmotion (which ball xrel yrel)
		     t)
     (:videoresize (w h)
		   t)
     (:videoexpose
      t)
     (:syswmevent
      t)
     (:quit 
      t)
     (:idle
      &body))
   NOTE: (:quit t) is mandatory if you ever want to exit your application."
  (let ((quit (gensym "quit")) (sdl-event (gensym "sdl-event")) (poll-event (gensym "poll-event")) 
        (previous-ticks (gensym "previous-ticks")) (current-ticks (gensym "current-ticks")))
    `(let ((,sdl-event (new-event))
           (,quit nil)
           (,previous-ticks nil)
           (,current-ticks nil))
      ;(init-framerate-manager)
      (do ()
	  ((eql ,quit t))
	(do ((,poll-event (SDL_PollEvent ,sdl-event) (SDL_PollEvent ,sdl-event)))
	    ((eql ,poll-event 0) nil)
	  (cond
            ,@(remove nil 
                      (mapcar #'(lambda (event)
                                  (case (first event)
                                    (:activeevent
                                     (expand-activeevent sdl-event 
                                                         (first (rest event)) 
                                                         (cons `(declare (ignore ,@(first (rest event))))
							       (rest (rest event)))))
				    (:keydown
				     (expand-keydown sdl-event 
						     (first (rest event)) 
						     (cons `(declare (ignore ,@(first (rest event))))
							   (rest (rest event)))))
				    (:keyup
				     (expand-keyup sdl-event 
						   (first (rest event)) 
						   (cons `(declare (ignore ,@(first (rest event))))
							 (rest (rest event)))))
				    (:mousemotion
				     (expand-mousemotion sdl-event 
							 (first (rest event)) 
							 (cons `(declare (ignore ,@(first (rest event))))
							       (rest (rest event)))))
				    (:mousebuttondown
				     (expand-mousebuttondown sdl-event
							     (first (rest event)) 
							     (cons `(declare (ignore ,@(first (rest event))))
								   (rest (rest event)))))
				    (:mousebuttonup
				     (expand-mousebuttonup sdl-event 
							   (first (rest event)) 
							   (cons `(declare (ignore ,@(first (rest event))))
								 (rest (rest event)))))
				    (:joyaxismotion
				     (expand-joyaxismotion sdl-event 
							   (first (rest event)) 
							   (cons `(declare (ignore ,@(first (rest event))))
								 (rest (rest event)))))
				    (:joybuttondown
				     (expand-joybuttondown sdl-event 
							   (first (rest event)) 
							   (cons `(declare (ignore ,@(first (rest event))))
								 (rest (rest event)))))
				    (:joybuttonup
				     (expand-joybuttonup sdl-event 
							 (first (rest event)) 
							 (cons `(declare (ignore ,@(first (rest event))))
							       (rest (rest event)))))
				    (:joyhatmotion
				     (expand-joyhatmotion sdl-event 
							  (first (rest event)) 
							  (cons `(declare (ignore ,@(first (rest event))))
								(rest (rest event)))))
				    (:joyballmotion
				     (expand-joyballmotion sdl-event 
							   (first (rest event)) 
							   (cons `(declare (ignore ,@(first (rest event))))
								 (rest (rest event)))))
				    (:videoresize
				     (expand-videoresize sdl-event 
							 (first (rest event)) 
							 (cons `(declare (ignore ,@(first (rest event))))
							       (rest (rest event)))))
				    (:videoexpose
				     (expand-videoexpose sdl-event 
							 (rest event)))
				    (:syswmevent
				     (expand-syswmevent sdl-event 
							(rest event)))
				    (:quit
				     (expand-quit sdl-event 
						  (rest event) 
						  quit))
				    (:userevent
				     (expand-userevent sdl-event 
						       (first (rest event)) 
						       (cons `(declare (ignore ,@(first (rest event))))
							     (rest (rest event)))))))
                              events))))
	(if (null ,previous-ticks)
	    (setf ,previous-ticks (SDL_GetTicks))
	    (setf ,previous-ticks ,current-ticks))
	(setf ,current-ticks (SDL_GetTicks))
	(set-timescale (/ 
			(set-ticks (- ,current-ticks ,previous-ticks)) 
			(get-worldtime)))
	,@(remove nil 
		  (mapcar #'(lambda (event)
			      (cond
				((eql :idle (first event))
				 (expand-idle (rest event)))))
			  events))
	(progn
	  (framerate-delay)))
      (cffi:foreign-free ,sdl-event))))

