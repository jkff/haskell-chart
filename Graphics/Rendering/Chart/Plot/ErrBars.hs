-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.Chart.Plot.ErrBars
-- Copyright   :  (c) Tim Docker 2006
-- License     :  BSD-style (see chart/COPYRIGHT)
--
-- Plot series of points with associated error bars.
--
{-# OPTIONS_GHC -XTemplateHaskell #-}

module Graphics.Rendering.Chart.Plot.ErrBars(
    PlotErrBars(..),
    defaultPlotErrBars,
    ErrPoint(..),
    ErrValue(..),
    symErrPoint,

    -- * Accessors
    -- | These accessors are generated by template haskell

    plot_errbars_title,
    plot_errbars_line_style,
    plot_errbars_tick_length,
    plot_errbars_overhang,
    plot_errbars_values,
) where

import Data.Accessor.Template
import qualified Graphics.Rendering.Cairo as C
import Graphics.Rendering.Chart.Types
import Graphics.Rendering.Chart.Renderable
import Graphics.Rendering.Chart.Plot.Types
import Data.Colour (opaque)
import Data.Colour.Names (black, blue)
import Data.Colour.SRGB (sRGB)

-- | Value for holding a point with associated error bounds for each axis.

data ErrValue x = ErrValue {
      ev_low  :: x,
      ev_best :: x,
      ev_high :: x
} deriving Show

data ErrPoint x y = ErrPoint {
      ep_x :: ErrValue x,
      ep_y :: ErrValue y
} deriving Show

-- | When the error is symmetric, we can simply pass in dx for the error.
symErrPoint :: (Num a, Num b) => a -> b -> a -> b -> ErrPoint a b
symErrPoint x y dx dy = ErrPoint (ErrValue (x-dx) x (x+dx))
                                 (ErrValue (y-dy) y (y+dy))

-- | Value defining a series of error intervals, and a style in
--   which to render them.
data PlotErrBars x y = PlotErrBars {
    plot_errbars_title_       :: String,
    plot_errbars_line_style_  :: CairoLineStyle,
    plot_errbars_tick_length_ :: Double,
    plot_errbars_overhang_    :: Double,
    plot_errbars_values_      :: [ErrPoint x y]
}


instance ToPlot PlotErrBars where
    toPlot p = Plot {
        plot_render_     = renderPlotErrBars p,
        plot_legend_     = [(plot_errbars_title_ p, renderPlotLegendErrBars p)],
        plot_all_points_ = ( concat [ [ev_low x,ev_high x]
                                    | ErrPoint x _ <- pts ]
                           , concat [ [ev_low y,ev_high y]
                                    | ErrPoint _ y <- pts ] )
    }
      where
        pts = plot_errbars_values_ p

renderPlotErrBars :: PlotErrBars x y -> PointMapFn x y -> CRender ()
renderPlotErrBars p pmap = preserveCState $ do
    mapM_ (drawErrBar.epmap) (plot_errbars_values_ p)
  where
    epmap (ErrPoint (ErrValue xl x xh) (ErrValue yl y yh)) =
        ErrPoint (ErrValue xl' x' xh') (ErrValue yl' y' yh')
        where (Point x' y')   = pmap' (x,y)
              (Point xl' yl') = pmap' (xl,yl)
              (Point xh' yh') = pmap' (xh,yh)
    drawErrBar = drawErrBar0 p
    pmap'      = mapXY pmap

drawErrBar0 ps (ErrPoint (ErrValue xl x xh) (ErrValue yl y yh)) = do
        let tl = plot_errbars_tick_length_ ps
        let oh = plot_errbars_overhang_ ps
        setLineStyle (plot_errbars_line_style_ ps)
        c $ C.newPath
        c $ C.moveTo (xl-oh) y
        c $ C.lineTo (xh+oh) y
        c $ C.moveTo x (yl-oh)
        c $ C.lineTo x (yh+oh)
        c $ C.moveTo xl (y-tl)
        c $ C.lineTo xl (y+tl)
        c $ C.moveTo (x-tl) yl
        c $ C.lineTo (x+tl) yl
        c $ C.moveTo xh (y-tl)
        c $ C.lineTo xh (y+tl)
        c $ C.moveTo (x-tl) yh
        c $ C.lineTo (x+tl) yh
	c $ C.stroke

renderPlotLegendErrBars :: PlotErrBars x y -> Rect -> CRender ()
renderPlotLegendErrBars p r@(Rect p1 p2) = preserveCState $ do
    drawErrBar (symErrPoint (p_x p1)              ((p_y p1 + p_y p2)/2) dx dx)
    drawErrBar (symErrPoint ((p_x p1 + p_x p2)/2) ((p_y p1 + p_y p2)/2) dx dx)
    drawErrBar (symErrPoint (p_x p2)              ((p_y p1 + p_y p2)/2) dx dx)

  where
    drawErrBar = drawErrBar0 p
    dx         = min ((p_x p2 - p_x p1)/6) ((p_y p2 - p_y p1)/2)

defaultPlotErrBars :: PlotErrBars x y
defaultPlotErrBars = PlotErrBars {
    plot_errbars_title_       = "",
    plot_errbars_line_style_  = solidLine 1 $ opaque blue,
    plot_errbars_tick_length_ = 3,
    plot_errbars_overhang_    = 0,
    plot_errbars_values_      = []
}

----------------------------------------------------------------------
-- Template haskell to derive an instance of Data.Accessor.Accessor
-- for each field.

$( deriveAccessors ''PlotErrBars )
