;;; Copyright (C) Mark Fedurin, 2011-2014.
;;;
;;; This file is part of ISoL.
;;;
;;; ISoL is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; ISoL is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with ISoL.  If not, see <http://www.gnu.org/licenses/>.

(in-package :isol)

;;; **************************************************************************
;;;  Graphics initialization and deinitialization
;;; **************************************************************************

(defun init-graphics ()
  (sdl2.kit:start))

(defun deinit-graphics ()
  (sdl2.kit:quit))

;;; **************************************************************************
;;;  Windows
;;; **************************************************************************

(defclass Window (sdl2.kit:gl-window) ())

(defun make-window (class &rest arguments)
  (apply #'make-instance class arguments))

(defmacro define-window (name (&rest additional-parents) &body slots)
  `(defclass ,name (Window ,@additional-parents)
     (,@slots)))

(defmacro define-window-init (name &body body)
  `(defmethod initialize-instance :after ((window ,name) &key &allow-other-keys)
     ,@body))

(defmacro define-window-render (name &body body)
  `(defmethod sdl2.kit:render ((window ,name))
     ,@body))

(defmacro define-window-close (name &body body)
  `(defmethod sdl2.kit:close-window ((window ,name))
     ,@body))

(defmacro define-window-event-handler (name &body body)
  `(defmethod sdl2.kit:window-event ((window ,name) type timestamp data1 data2)
     ,@body))

;;; TODO Move FPS somewhere where I can tweak it easily.
(defmethod initialize-instance :after ((window Window)
                                       &key (w 800) (h 600) &allow-other-keys)
  (setf (sdl2.kit:idle-render window) t)
  ;; OpenGL
  (gl:viewport 0 0 w h)
  (gl:matrix-mode :projection)
  (gl:ortho 0 w 0 h -1 1)
  (gl:matrix-mode :modelview)
  (gl:enable :texture-2d
             :blend)
  (gl:disable :multisample)
  (gl:hint :texture-compression-hint :nicest)
  (gl:blend-func :src-alpha :one-minus-src-alpha)
  (gl:load-identity))

(defmethod sdl2.kit:close-window ((window Window))
  (call-next-method))

;;; **************************************************************************
;;;  VAOs
;;; **************************************************************************

(defclass VAO ()
  ((pointer :initarg :pointer)
   (length :initarg :length)))

(defun make-vao (data)
  (let ((float-size 4)
        (vao (gl:gen-vertex-array))
        (vbo (first (gl:gen-buffers 1))))
    (gl:bind-vertex-array vao)
    (gl:bind-buffer :array-buffer vbo)
    (with-foreign-vector (data-ptr :float data)
      (%gl:buffer-data :array-buffer (* float-size (length data)) data-ptr :static-draw))
    (gl:enable-client-state :vertex-array)
    (%gl:vertex-pointer 2 :float (* 4 float-size) (cffi:make-pointer 0))
    (gl:enable-client-state :texture-coord-array)
    (%gl:tex-coord-pointer 2 :float (* 4 float-size) (cffi:make-pointer (* float-size 2)))
    (gl:bind-vertex-array 0)
    (gl:delete-buffers (list vbo))
    (make-instance 'VAO
                   :pointer vao
                   :length (/ (length data) 4))))

(defun make-vaos (&rest data)
  (loop for dat in data
        collecting (make-vao dat)))

(defgeneric enable-vao (vao))

(defmethod enable-vao ((vao VAO))
  (with-slots (pointer) vao
    (gl:bind-vertex-array pointer)))

;;; **************************************************************************
;;;  Textures
;;; **************************************************************************

(defclass Texture ()
  ((pointer :initarg :pointer)
   (vao :initarg :vao)
   (width :initarg :width)
   (height :initarg :height)))

(defun copy-image-to-foreign-memory (pointer image)
  (with-slots (width height channels data) image
    (opticl:do-pixels (j i) data
      (multiple-value-bind (r g b a) (opticl:pixel data (- height j 1) i)
        (let* ((pixel-start-index (* 4 (+ (* j width) i)))
               (r-index pixel-start-index)
               (g-index (+ 1 pixel-start-index))
               (b-index (+ 2 pixel-start-index))
               (a-index (+ 3 pixel-start-index)))
          (setf (cffi:mem-aref pointer :unsigned-char r-index) r
                (cffi:mem-aref pointer :unsigned-char g-index) g
                (cffi:mem-aref pointer :unsigned-char b-index) b
                (cffi:mem-aref pointer :unsigned-char a-index) a))))))

(defun copy-cairo-image-to-foreign-memory (pointer data w h)
  (dotimes (i h)
    (dotimes (j w)
      (let* ((pixel-start-index (* 4 (+ (* (- h i 1) w) j)))
             (pixel-start-index-transpose (* 4 (+ (* (- w j 1) h) i)))
             (r (cffi:mem-aref data :unsigned-char pixel-start-index))
             (g (cffi:mem-aref data :unsigned-char (+ 1 pixel-start-index)))
             (b (cffi:mem-aref data :unsigned-char (+ 2 pixel-start-index)))
             (a (cffi:mem-aref data :unsigned-char (+ 3 pixel-start-index))))
        (setf (cffi:mem-aref pointer :unsigned-char pixel-start-index-transpose) r
              (cffi:mem-aref pointer :unsigned-char (+ 1 pixel-start-index-transpose)) g
              (cffi:mem-aref pointer :unsigned-char (+ 2 pixel-start-index-transpose)) b
              (cffi:mem-aref pointer :unsigned-char (+ 3 pixel-start-index-transpose)) a)))))

(defun make-gl-texture (target mipmap-level image &key border?)
  (with-slots (width height channels format data) image
    (let ((texture (first (gl:gen-textures 1))))
      (gl:bind-texture target texture)
      (gl:tex-parameter target :generate-mipmap t)
      (gl:tex-parameter target :texture-min-filter :nearest)
      (gl:tex-parameter target :texture-mag-filter :nearest)
      (cffi:with-foreign-object (pointer :unsigned-char (* width height channels))
        (cond
          ((cffi:pointerp data)
           (copy-cairo-image-to-foreign-memory pointer data width height)
           (gl:tex-image-2d target mipmap-level
                            format height width (if border? 1 0)
                            format :unsigned-byte
                            pointer))
          (t
           (copy-image-to-foreign-memory pointer image)
           (gl:tex-image-2d target mipmap-level
                            format width height (if border? 1 0)
                            format :unsigned-byte
                            pointer))))
      texture)))

(defun make-texture (target mipmap-level image &key border?)
  (with-slots (width height) image
    (make-instance 'Texture
                   :pointer (make-gl-texture target mipmap-level image :border? border?)
                   :vao (make-vao (vector 0.0 0.0                      0.0 0.0
                                          (float width) 0.0            1.0 0.0
                                          (float width) (float height) 1.0 1.0
                                          0.0 (float height)           0.0 1.0))
                   :width width
                   :height height)))

(defgeneric enable-texture (target texture))

(defmethod enable-texture (target (texture Texture))
  (with-slots (pointer) texture
    (gl:bind-texture target pointer)))

;;; **************************************************************************
;;;  Texture atlases
;;; **************************************************************************

;;; TODO Make atlases support textures with unequal frames
(defclass Texture-atlas (Texture)
  ((n-frames-x :initarg :n-frames-x)
   (n-frames-y :initarg :n-frames-y)
   (current-frame-x :initarg :current-frame-x)
   (current-frame-y :initarg :current-frame-y)
   (frame-size-x)
   (frame-size-y)
   (all-vaos)))

(defun calculate-atlas-rects (atlas)
  (with-slots (frame-size-x frame-size-y n-frames-x n-frames-y width height) atlas
    (loop
      for i below n-frames-x
      appending
      (loop
        for j below n-frames-y
        collecting (vector 0.0 0.0      (* frame-size-x i) (* frame-size-y j)
                           width 0.0    (* frame-size-x (1+ i)) (* frame-size-y j)
                           width height (* frame-size-x (1+ i)) (* frame-size-y (1+ j))
                           0.0 height   (* frame-size-x i) (* frame-size-y (1+ j)))))))

(defun get-atlas-current-rect (atlas)
  (with-slots (n-frames-y current-frame-x current-frame-y all-vaos) atlas
    (nth (+ (* current-frame-y n-frames-y) current-frame-x) all-vaos)))

(defmethod initialize-instance :after ((instance Texture-atlas) &key &allow-other-keys)
  (with-slots (n-frames-x n-frames-y
               width height
               current-frame-x current-frame-y
               frame-size-x frame-size-y
               vao all-vaos
               sequence)
      instance
    (setf frame-size-x (/ 1.0 n-frames-x)
          frame-size-y (/ 1.0 n-frames-y)
          current-frame-x (first (first sequence))
          current-frame-y (second (first sequence))
          all-vaos     (apply #'make-vaos (calculate-atlas-rects instance))
          vao          (get-atlas-current-rect instance))))

(defgeneric switch-texture-frame (texture new-frame-x new-frame-y))

(defmethod switch-texture-frame ((texture Texture-atlas) new-frame-x new-frame-y)
  (with-slots (current-frame-x current-frame-y vao) texture
    (setf current-frame-x new-frame-x
          current-frame-y new-frame-y
          vao (get-atlas-current-rect texture))))

(defun make-texture-atlas (size-x size-y target mipmap-level image &key border?)
  (with-slots (width height) image
    (make-instance 'Texture-atlas
                   :pointer (make-gl-texture target mipmap-level image :border? border?)
                   :n-frames-x size-x
                   :n-frames-y size-y
                   :width width
                   :height height)))

;;; **************************************************************************
;;;  Animations
;;; **************************************************************************

(defclass Animated-texture (Texture-atlas)
  ((frame-rate :initarg :frame-rate)
   (counter :initform 0)
   (sequence :initarg :sequence)
   (current-frame :initform 0)))

(defgeneric next-frame (textute))
(defgeneric animation-tick (texture))

(defmethod next-frame ((texture Animated-texture))
   (with-slots (sequence current-frame current-frame-x current-frame-y) texture
     (mod-incf current-frame (length sequence))
     (destructuring-bind (x y) (elt sequence current-frame)
       (setf current-frame-x x
             current-frame-y y))
     (switch-texture-frame texture current-frame-x current-frame-y)))

(defmethod animation-tick ((texture Animated-texture))
  (with-slots (frame-rate counter) texture
    (incf counter)
    (when (>= counter frame-rate)
      (setf counter 0)
      (next-frame texture))))

(defun make-animated-texture (size-x size-y sequence frame-rate target mipmap-level image &key border?)
  (with-slots (width height) image
    (make-instance 'Animated-texture
                   :pointer (make-gl-texture target mipmap-level image :border? border?)
                   :n-frames-x size-x
                   :n-frames-y size-y
                   :sequence sequence
                   :frame-rate frame-rate
                   :width (float (/ width size-x))
                   :height (float (/ height size-y)))))

;;; **************************************************************************
;;;  Sprites
;;; **************************************************************************

(defclass Sprite ()
  ((position-x :initarg :position-x
               :accessor sprite-position-x)
   (position-y :initarg :position-y
               :accessor sprite-position-y)
   (scale :initarg :scale
          :accessor sprite-scale)
   (rotation :initarg :rotation
             :accessor sprite-rotation)
   (texture :initarg :texture
            :accessor sprite-texture)))

(defgeneric draw (object))

(defmethod draw ((sprite Sprite))
  ;; Sprites are mostly rectangles. At least rectangles are easier to work with.
  (with-slots (position-x position-y scale rotation texture) sprite
    (gl:push-matrix)
    (gl:load-identity)
    (gl:translate position-x position-y 0.0)
    (destructuring-bind (x y) scale
      (gl:scale x y 1.0))
    (destructuring-bind (x y z) rotation
      (gl:rotate x 1.0 0.0 0.0)
      (gl:rotate y 0.0 1.0 0.0)
      (gl:rotate z 0.0 0.0 1.0))
    (enable-texture :texture-2d texture)
    (with-slots (vao) texture
      (enable-vao vao)
      (%gl:draw-arrays :quads 0 (slot-value vao 'length)))
    (gl:pop-matrix)))

(defun make-sprite (texture x y &key (scale (list 1.0 1.0)) (rotation (list 0.0 0.0 0.0)))
  (make-instance 'Sprite
                 :position-x x
                 :position-y y
                 :scale scale
                 :rotation rotation
                 :texture texture))

;;; **************************************************************************
;;;  Text
;;; **************************************************************************

(defclass Text (Sprite)
  ((font :initarg :font
         :initform "Times"
         :accessor text-font)
   (width :initarg :width
          :accessor text-width)
   (height :initarg :height
           :accessor text-height)
   (content :initarg :content
            :accessor text-content)
   (size :initarg :size
         :initform nil
         :accessor text-size)
   (color :initarg :color
          :initform (list 0 0 0 255)
          :accessor text-color)))

(defun draw-text (text)
  (with-slots (font color size width height content) text
    (let* ((surface (cairo:create-image-surface :argb32 width height))
           (context (cairo:create-context surface)))
      (cairo:with-context (context)
        (destructuring-bind (r g b a) color
          (cairo:set-source-rgba r g b a))
        (cairo:select-font-face font :normal :normal)
        (cairo:set-font-size (or size (* 0.7 height)))
        (cairo:move-to (* width 0.01) (* height 0.7))
        (cairo:show-text content))
      (cairo:destroy context)
      surface)))

(defun render-text-texture (text)
  (with-slots (width height texture) text
    (let* ((surface (draw-text text))
           (data (cairo:image-surface-get-data surface :pointer-only t))
           (image (make-instance 'Image
                                 :format :rgba
                                 :channels 4
                                 :width width
                                 :height height
                                 :data data)))
      (setf texture (make-texture :texture-2d 0 image))
      (cairo:destroy surface))))

(defmethod initialize-instance :after ((instance Text) &rest initargs)
  (declare (ignore initargs))
  (with-slots (width height surface context texture) instance
    (render-text-texture instance)))

(defgeneric update-content (new-content instance))

(defmethod update-content (new-content (instance Text))
  (with-slots (content) instance
    (setf content new-content)
    (draw-text instance)
    (render-text-texture instance)))

(defun make-text (content x y w h
                  &key (font "Times") size
                  (scale (list 1.0 1.0)) (rotation (list 0.0 0.0 0.0)))
  (make-instance 'Text
                 :content content
                 :position-x x
                 :position-y y
                 :scale scale
                 :rotation rotation
                 :width w
                 :height h
                 :font font
                 :size size))
