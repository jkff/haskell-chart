-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.Chart.Renderable
-- Copyright   :  (c) Tim Docker 2006
-- License     :  BSD-style (see chart/COPYRIGHT)
--
-- This module contains the definition of the 'Renderable' type, which
-- is a composable drawing element, along with assorted functions to
-- them.
--

module Graphics.Rendering.Chart.Renderable(
    Renderable(..),
    ToRenderable(..),
    PickFn,

    renderableToPNGFile,
    renderableToPDFFile,
    renderableToPSFile,
    renderableToSVGFile,

    vectorEnv,
    bitmapEnv,

    fillBackground,
    addMargins,
    emptyRenderable,
    embedRenderable,
    label,
    rlabel,
    spacer,
    spacer1,
    setPickFn,
    mapMaybePickFn,
    mapPickFn,
    nullPickFn,

    rect_minsize,
    rect_fillStyle,
    rect_lineStyle,
    rect_cornerStyle,
) where

import qualified Graphics.Rendering.Cairo as C
import qualified Graphics.Rendering.Cairo.Matrix as Matrix
import Control.Monad
import Data.Accessor
import Data.List ( nub, transpose, sort )

import Graphics.Rendering.Chart.Types

-- | A function that maps a point in device coordinates to some value.
--
--   Perhaps it might be generalised from Maybe a to
--   (MonadPlus m ) => m a in the future.
type PickFn a = Point -> (Maybe a)

nullPickFn :: PickFn a
nullPickFn = const Nothing

-- | A Renderable is a record of functions required to layout a
--   graphic element.
data Renderable a = Renderable {

   -- | A Cairo action to calculate a minimum size.
   minsize :: CRender RectSize,

   -- | A Cairo action for drawing it within a rectangle.
   --   The rectangle is from the origin to the given point.
   --
   --   The resulting "pick" function  maps a point in the image to a value.
   render  ::  RectSize -> CRender (PickFn a)
}

-- | A type class abtracting the conversion of a value to a Renderable.
class ToRenderable a where
   toRenderable :: a -> Renderable ()

emptyRenderable :: Renderable a
emptyRenderable = spacer (0,0)

-- | Create a blank renderable with a specified minimum size.
spacer :: RectSize -> Renderable a 
spacer sz  = Renderable {
   minsize = return sz,
   render  = \_ -> return nullPickFn
}


-- | Create a blank renderable with a minimum size the same as
--   some other renderable.
spacer1 :: Renderable a -> Renderable b
spacer1 r  = r{ render  = \_ -> return nullPickFn }

-- | Replace the pick function of a renderable with another.
setPickFn :: PickFn b -> Renderable a -> Renderable b
setPickFn pickfn r = r{ render  = \sz -> do { render r sz; return pickfn; } }

-- | Map a function over the result of a renderable's pickfunction, keeping only 'Just' results.
mapMaybePickFn :: (a -> Maybe b) -> Renderable a -> Renderable b
mapMaybePickFn f r = r{ render = \sz -> do pf <- render r sz
                                           return (join . fmap f . pf) }

-- | Map a function over result of a renderable's pickfunction.
mapPickFn :: (a -> b) -> Renderable a -> Renderable b
mapPickFn f = mapMaybePickFn (Just . f)

-- | Add some spacing at the edges of a renderable.
addMargins :: (Double,Double,Double,Double) -- ^ The spacing to be added.
           -> Renderable a                  -- ^ The source renderable.
           -> Renderable a
addMargins (t,b,l,r) rd = Renderable { minsize = mf, render = rf }
  where
    mf = do
        (w,h) <- minsize rd
        return (w+l+r,h+t+b)

    rf (w,h) = do
        preserveCState $ do
            c $ C.translate l t
            pickf <- render rd (w-l-r,h-t-b)
            return (mkpickf pickf (t,b,l,r) (w,h))

    mkpickf pickf (t,b,l,r) (w,h) (Point x y)
        | x >= l && x <= w-r && y >= t && t <= h-b = pickf (Point (x-l) (y-t))
        | otherwise                                = Nothing

-- | Overlay a renderable over a solid background fill.
fillBackground :: CairoFillStyle -> Renderable a -> Renderable a
fillBackground fs r = r{ render = rf }
  where
    rf rsize@(w,h) = do
        preserveCState $ do
            setClipRegion (Point 0 0) (Point w h)
            setFillStyle fs
            c $ C.paint
	render r rsize

-- | Output the given renderable to a PNG file of the specifed size
--   (in pixels), to the specified file.
renderableToPNGFile :: Renderable a -> Int -> Int -> FilePath -> IO (PickFn a)
renderableToPNGFile chart width height path = 
    C.withImageSurface C.FormatARGB32 width height $ \result -> do
    pick <- C.renderWith result $ runCRender rfn bitmapEnv
    C.surfaceWriteToPNG result path
    return pick
  where
    rfn = do
	render chart (fromIntegral width, fromIntegral height)

renderableToFile withSurface chart width height path = 
    withSurface path (fromIntegral width) (fromIntegral height) $ \result -> do
    C.renderWith result $ runCRender rfn vectorEnv
    C.surfaceFinish result
  where
    rfn = do
        render chart (fromIntegral width, fromIntegral height)
        c $ C.showPage

-- | Output the given renderable to a PDF file of the specifed size
--   (in points), to the specified file.
renderableToPDFFile :: Renderable a -> Int -> Int -> FilePath -> IO ()
renderableToPDFFile = renderableToFile C.withPDFSurface

-- | Output the given renderable to a postscript file of the specifed size
--   (in points), to the specified file.
renderableToPSFile  :: Renderable a -> Int -> Int -> FilePath -> IO ()
renderableToPSFile  = renderableToFile C.withPSSurface

-- | Output the given renderable to an SVG file of the specifed size
--   (in points), to the specified file.
renderableToSVGFile :: Renderable a -> Int -> Int -> FilePath -> IO ()
renderableToSVGFile = renderableToFile C.withSVGSurface

bitmapEnv :: CEnv
bitmapEnv = CEnv (adjfn 0.5) (adjfn 0.0)
  where
    adjfn offset (Point x y) = Point (adj x) (adj y)
      where
        adj v = (fromIntegral.round) v +offset

vectorEnv :: CEnv
vectorEnv = CEnv id id

-- | Helper function for using a renderable, when we generate it
--   in the CRender monad.
embedRenderable :: CRender (Renderable a) -> Renderable a
embedRenderable ca = Renderable {
   minsize = do { a <- ca; minsize a },
   render  = \ r -> do { a <- ca; render a r }
}


----------------------------------------------------------------------
-- Labels

-- | Construct a renderable from a text string, aligned with the axes.
label :: CairoFontStyle -> HTextAnchor -> VTextAnchor -> String
         -> Renderable String
label fs hta vta = rlabel fs hta vta 0

-- | Construct a renderable from a text string, rotated wrt to axes. The angle
--   of rotation is in degrees.
rlabel :: CairoFontStyle -> HTextAnchor -> VTextAnchor -> Double -> String
          -> Renderable String
rlabel fs hta vta rot s = Renderable { minsize = mf, render = rf }
  where
    mf = preserveCState $ do
       setFontStyle fs
       (w,h) <- textSize s
       return (w*acr+h*asr,w*asr+h*acr)
    rf (w0,h0) = preserveCState $ do
       setFontStyle fs
       sz@(w,h) <- textSize s
       fe <- c $ C.fontExtents
       c $ C.translate 0 (-C.fontExtentsDescent fe)
       c $ C.translate (xadj sz hta 0 w0) (yadj sz vta 0 h0)
       c $ C.rotate rot'
       c $ C.moveTo (-w/2) (h/2)
       c $ C.showText s
       return (\_-> Just s)  -- PickFn String
    xadj (w,h) HTA_Left   x1 x2 =  x1 +(w*acr+h*asr)/2
    xadj (w,h) HTA_Centre x1 x2 = (x1 + x2)/2
    xadj (w,h) HTA_Right  x1 x2 =  x2 -(w*acr+h*asr)/2
    yadj (w,h) VTA_Top    y1 y2 =  y1 +(w*asr+h*acr)/2
    yadj (w,h) VTA_Centre y1 y2 = (y1+y2)/2
    yadj (w,h) VTA_Bottom y1 y2 =  y2 - (w*asr+h*acr)/2

    rot'      = rot / 180 * pi
    (cr,sr)   = (cos rot', sin rot')
    (acr,asr) = (abs cr, abs sr)

----------------------------------------------------------------------
-- Rectangles

data RectCornerStyle = RCornerSquare
                     | RCornerBevel Double
                     | RCornerRounded Double

data Rectangle = Rectangle {
  rect_minsize_     :: RectSize,
  rect_fillStyle_   :: Maybe CairoFillStyle,
  rect_lineStyle_   :: Maybe CairoLineStyle,
  rect_cornerStyle_ :: RectCornerStyle
}

-- | Accessor for field rect_minsize_.
rect_minsize :: Accessor Rectangle RectSize
rect_minsize     = accessor (\v->rect_minsize_ v)
                            (\a v -> v{rect_minsize_=a})

-- | Accessor for field rect_fillStyle_.
rect_fillStyle :: Accessor Rectangle (Maybe CairoFillStyle)
rect_fillStyle   = accessor (\v->rect_fillStyle_ v)
                            (\a v -> v{rect_fillStyle_=a})

-- | Accessor for field rect_lineStyle_.
rect_lineStyle :: Accessor Rectangle (Maybe CairoLineStyle)
rect_lineStyle   = accessor (\v->rect_lineStyle_ v)
                            (\a v -> v{rect_lineStyle_=a})

-- | Accessor for field rect_cornerStyle_.
rect_cornerStyle :: Accessor Rectangle RectCornerStyle
rect_cornerStyle = accessor (\v->rect_cornerStyle_ v)
                            (\a v -> v{rect_cornerStyle_=a})


defaultRectangle :: Rectangle
defaultRectangle = Rectangle {
  rect_minsize_     = (0,0),
  rect_fillStyle_   = Nothing,
  rect_lineStyle_   = Nothing,
  rect_cornerStyle_ = RCornerSquare
}

instance ToRenderable Rectangle where
   toRenderable rectangle = Renderable mf rf
     where
      mf    = return (rect_minsize_ rectangle)
      rf sz = preserveCState $ do
        maybeM () (fill sz) (rect_fillStyle_ rectangle)
        maybeM () (stroke sz) (rect_lineStyle_ rectangle)
        return nullPickFn

      fill sz fs = do
          setFillStyle fs
          strokeRectangle sz (rect_cornerStyle_ rectangle)
          c $ C.fill

      stroke sz ls = do
          setLineStyle ls
          strokeRectangle sz (rect_cornerStyle_ rectangle)
          c $ C.stroke

      strokeRectangle (x2,y2) RCornerSquare = c $ do
          let (x1,y1) = (0,0)
          C.moveTo x1 y1
          C.lineTo x1 y2
          C.lineTo x2 y2
          C.lineTo x2 y1
          C.lineTo x1 y1
          C.lineTo x1 y2
                                  
      strokeRectangle (x2,y2) (RCornerBevel s) = c $ do
          let (x1,y1) = (0,0)
          C.moveTo x1 (y1+s)
          C.lineTo x1 (y2-s)
          C.lineTo (x1+s) y2
          C.lineTo (x2-s) y2
          C.lineTo x2 (y2-s)
          C.lineTo x2 (y1+s)
          C.lineTo (x2-s) y1
          C.lineTo (x1+s) y1
          C.lineTo x1 (y1+s)
          C.lineTo x1 (y2-s)

      strokeRectangle (x2,y2) (RCornerRounded s) = c $ do
          let (x1,y1) = (0,0)
          C.arcNegative (x1+s) (y2-s) s (pi2*2) pi2 
          C.arcNegative (x2-s) (y2-s) s pi2 0
          C.arcNegative (x2-s) (y1+s) s 0 (pi2*3)
          C.arcNegative (x1+s) (y1+s) s (pi2*3) (pi2*2)
          C.lineTo x1 (y2-s)

      pi2 = pi / 2

