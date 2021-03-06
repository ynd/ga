(in-package :ga)

(defun make-bitmap (width height &optional (bg (make-instance 'color)))
  "A bitmap is simply a 2d array of color objects. This creates a blank bitmap"
  (make-array (list width height) :element-type 'color :initial-element bg))

(defun get-pixel-bmp (bmp pixel-x pixel-y)
  (aref bmp pixel-x pixel-y))

(defun (setf get-pixel-bmp) (new-value bmp pixel-x pixel-y)
  "Take care of alpha blending when I overwrite a square with an existing color"
  (setf (aref bmp pixel-x pixel-y) 
	(combine-pixels (get-pixel-bmp bmp pixel-x pixel-y) new-value)))

;;fitness function
(defun difference-bmps (a b width height)
  "Compute how different two bitmaps (a and b), of the same size are. Uses the color-distance heuristic"
  (loop for x from 0 upto (1- width) 
     with res = 0
     do (loop for y from 0 upto (1- height)
	   do (incf res (color-distance (get-pixel-bmp a x y) (get-pixel-bmp b x y))))
     finally (return res)))

(defun write-bmp-file (bmp file)
  "Write a bmp (a 2d array of colors) to a file on the filesystem as a valid Bitmap (BMP) file"
  (declare (type (simple-array color) bmp))
  (destructuring-bind (width height)
      (array-dimensions bmp)
    (let* ((padding-per-row (mod (* width 3) 4))
	  (total-padding (* padding-per-row height)))
      (with-open-file (stream file :direction :output 
			      :element-type 'unsigned-byte
			      :if-exists :supersede)
	(write-byte 66 stream)
	(write-byte 77 stream) ;;these two are the bmp "Magic Number"
	(write-int32 (+ 54 (* 3 width height) total-padding) stream) ;;the file size
	(write-int32 0 stream)	 ;;reserved 4 bytes
	(write-int32 54 stream)	 ;;data offset
	(write-int32 40 stream)	 ;;remaining bytes in header
	(write-int32 width stream) ;;width
	(write-int32 height stream) ;;height
	(write-int16 1 stream)	    ;;color-planes
	(write-int16 24 stream)	    ;;bits/pixel
	(write-int32 0 stream)	    ;;no compression
	(write-int32 (+ total-padding (* 3 width height)) stream) ;;data size
	(write-int32 2835 stream) ;;desired horizontal resolution in pixels/inch
	(write-int32 2835 stream) ;;desired vertical resolution in pixels/inch
	(write-int32 0 stream)	  ;;no palette - TrueColor
	(write-int32 0 stream)	  ;;All colors are important
      
	;;actually write image
	(loop for y from (1- height) downto 0
	   do (progn  
		(loop for x from 0 upto (1- width)
		   do (write-int24 (color-to-rgb (get-pixel-bmp bmp x y)) stream))
		(loop for x from 1 upto padding-per-row do
		     (write-byte 0 stream)))))))) ;;rows need padding so that rows are a multiple of 4 bytes per row

(defun read-bmp-file (file)
  "Read a bitmap from a file into a 2d array of colors"
  (with-open-file (stream file :direction :input
			  :element-type 'unsigned-byte
			  :if-does-not-exist :error)
    (if (and (= 66 (read-byte stream))
	     (= 77 (read-byte stream))) ;;make sure the magic number is right (i.e., this is a real bmp)
	(let ((w 0)
	      (h 0)
	      (padding 0)
	      (bmp nil))
	  (read-int32 stream) ;;total size - disregard
	  (read-int32 stream) ;;reserved - disregard
	  (let* ((header-total (read-int32 stream))   ;;make sure the data offset and header size are as expected
		 (header-remaining (read-int32 stream)))
	    (when (not (and (= 54 header-total)
			    (= 40 header-remaining)))
	      (error "I don't know how to read this bitmap file's header. (~A,~A)" header-total header-remaining)))
	  (setf w (read-int32 stream)) ;;get the size
	  (setf h (read-int32 stream))
	  (setf padding (mod (* w 3) 4)) ;;figure out how much padding there is per row
	  (setf bmp (make-bitmap w h)) ;;allocate memory for the bmp array
	  (when (not (and (= 1 (read-int16 stream)) ;;make sure that this is a 24bit trucolor bitmap
			  (= 24 (read-int16 stream))
			  (= 0 (read-int32 stream))))
	    (error "I don't know how to read this bitmap's data (unknown bit depth or compression"))
	  (read-int32 stream)		;ignore data size
	  (read-int32 stream)		;ignore horizontal resolution
	  (read-int32 stream)		;ignore vertical resolution
	  (when (not (and (= 0 (read-int32 stream)) ;;TrueColor Bitmaps shouldn't have a palette.
			  (= 0 (read-int32 stream))))
	    (error "I don't know how to read this bitmap's palette. Only support TrueColor RGB"))
	  (loop for y from (1- h) downto 0
	       do (progn 
		    (loop for x from 0 upto (1- w)
		       do (setf (get-pixel-bmp bmp x y) (rgb-to-color (read-int24 stream)))) ;;actually read the data
		    (loop for x from 1 upto padding do (read-int24 stream)))
	       finally (return bmp)))
	(error "File appears to not be a bitmap"))))