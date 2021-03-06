-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.Chart.Layout
-- Copyright   :  (c) Tim Docker 2006
-- License     :  BSD-style (see chart/COPYRIGHT)
--
-- This module glues together axes and plots to actually create a renderable
-- for a chart.
--
-- Note that template haskell is used to derive accessor functions
-- (see 'Data.Accessor') for each field of the following data types:
--
--     * 'Layout1'
--
--     * 'LayoutAxis'
--
-- These accessors are not shown in this API documentation.  They have
-- the same name as the field, but with the trailing underscore
-- dropped. Hence for data field f_::F in type D, they have type
--
-- @
--   f :: Data.Accessor.Accessor D F
-- @
--

{-# OPTIONS_GHC -XTemplateHaskell #-}

module Graphics.Rendering.Chart.Layout(
    Layout1(..),
    LayoutAxis(..),
    Layout1Pick(..),
    MAxisFn,

    defaultLayout1,
    layout1ToRenderable,
    linkAxes,
    independentAxes,

    updateAllAxesStyles,
    setLayout1Foreground,

    defaultLayoutAxis,
    laxis_title_style,
    laxis_title,
    laxis_style,
    laxis_visible,
    laxis_generate,
    laxis_override,
    laxis_reverse,

    layout1_background,
    layout1_plot_background,
    layout1_title,
    layout1_title_style,
    layout1_left_axis,
    layout1_right_axis,
    layout1_top_axis,
    layout1_bottom_axis,
    layout1_yaxes_control,
    layout1_margin,
    layout1_plots,
    layout1_legend,
    layout1_grid_last,

    renderLayout1sStacked,
    AnyLayout1(),
    withAnyOrdinate
  ) where

import qualified Graphics.Rendering.Cairo as C

import Graphics.Rendering.Chart.Axis
import Graphics.Rendering.Chart.Types
import Graphics.Rendering.Chart.Plot
import Graphics.Rendering.Chart.Legend
import Graphics.Rendering.Chart.Renderable
import Graphics.Rendering.Chart.Grid
import Control.Monad
import Control.Monad.Reader (local)
import Data.Accessor.Template
import Data.Accessor
import Data.Colour
import Data.Colour.Names (white)

-- | A @MAxisFn@ is a function that generates an (optional) axis
--   given the points plotted against that axis.
type MAxisFn t = [t] -> Maybe (AxisData t)

data LayoutAxis x = LayoutAxis {
   laxis_title_style_ :: CairoFontStyle,
   laxis_title_       :: String,
   laxis_style_       :: AxisStyle,

   -- | Function that determines whether an axis should be visible,
   --   based upon the points plotted on this axis. The default value
   --   is 'not.null'.
   laxis_visible_     :: [x] -> Bool,

   -- | Function that generates the axis data, based upon the
   --   points plotted. The default value is 'autoAxis'.
   laxis_generate_    :: AxisFn x,

   -- | Function that can be used to override the generated axis data.
   --   The default value is 'id'.
   laxis_override_    :: AxisData x -> AxisData x,

   -- | True if left to right (bottom to top) is to show descending values.
   laxis_reverse_     :: Bool

}

-- | A Layout1 value is a single plot area, with optional: axes on
--   each of the 4 sides; title at the top; legend at the bottom. It's
--   parameterised by the types of values to be plotted on the horizonal
--   and vertical axes.
data Layout1 x y = Layout1 {

    layout1_background_      :: CairoFillStyle,
    layout1_plot_background_ :: Maybe CairoFillStyle,

    layout1_title_           :: String,
    layout1_title_style_     :: CairoFontStyle,

    layout1_bottom_axis_     :: LayoutAxis x,
    layout1_top_axis_        :: LayoutAxis x,
    layout1_left_axis_       :: LayoutAxis y,
    layout1_right_axis_      :: LayoutAxis y,

    -- | Function to map points from the left/right plot
    --   to the left/right axes. The default value is 'id'.
    layout1_yaxes_control_   :: ([y],[y]) -> ([y],[y]),

    layout1_margin_          :: Double,
    layout1_plots_           :: [Either (Plot x y) (Plot x y)],
    layout1_legend_          :: Maybe LegendStyle,

    -- | True if the grid is to be rendered on top of the Plots.
    layout1_grid_last_       :: Bool
}

data Layout1Pick x y = L1P_Legend String
                     | L1P_Title String
                     | L1P_BottomAxisTitle String
                     | L1P_TopAxisTitle String
                     | L1P_LeftAxisTitle String
                     | L1P_RightAxisTitle String
                     | L1P_PlotArea x y y
                     | L1P_BottomAxis x
                     | L1P_TopAxis x
                     | L1P_LeftAxis y
                     | L1P_RightAxis y
    deriving (Show)

instance (Ord x, Ord y) => ToRenderable (Layout1 x y) where
    toRenderable = setPickFn nullPickFn.layout1ToRenderable

-- | Encapsulates a 'Layout1' with a fixed abscissa type but
--   arbitrary ordinate type.
data AnyLayout1 x = AnyLayout1 {
    background       :: CairoFillStyle,
    titleRenderable  :: Renderable (),
    plotAreaGrid     :: Grid (Renderable ()),
    legendRenderable :: Renderable (),
    margin           :: Double
  }

withAnyOrdinate :: (Ord x,Ord y) => Layout1 x y -> AnyLayout1 x
withAnyOrdinate l = AnyLayout1 {
    background       = layout1_background_ l,
    titleRenderable  = mapPickFn (const ()) $ layout1TitleToRenderable l,
    plotAreaGrid     = fmap (mapPickFn (const ())) $ layout1PlotAreaToGrid l,
    legendRenderable = mapPickFn (const ()) $ layout1LegendsToRenderable l,
    margin           = layout1_margin_ l
  }


-- | Render several layouts with the same abscissa type stacked so that their
--   origins and axis titles are aligned horizontally with respect to each
--   other.  The exterior margins and background are taken from the first
--   element.
renderLayout1sStacked :: (Ord x) => [AnyLayout1 x] -> Renderable ()
renderLayout1sStacked []        = emptyRenderable
renderLayout1sStacked ls@(l1:_) = gridToRenderable g
  where
    g = fullOverlayUnder (fillBackground (background l1) emptyRenderable)
        $ addMarginsToGrid (lm,lm,lm,lm)
        $ aboveN [ fullRowAbove (titleRenderable l) 0 (
                       fullRowBelow (legendRenderable l) 0
                           (plotAreaGrid l))
                 | l <- ls ]

    lm = margin l1

addMarginsToGrid :: (Double,Double,Double,Double) -> Grid (Renderable a)
                    -> Grid (Renderable a)
addMarginsToGrid (t,b,l,r) g = aboveN [
     besideN [er, ts, er],
     besideN [ls, g,  rs],
     besideN [er, bs, er]
  ]
  where
    er = empty
    ts = tval $ spacer (0,t)
    ls = tval $ spacer (l,0)
    bs = tval $ spacer (0,b)
    rs = tval $ spacer (r,0)

layout1ToRenderable :: (Ord x, Ord y) =>
                       Layout1 x y -> Renderable (Layout1Pick x y)
layout1ToRenderable l =
   fillBackground (layout1_background_ l) $ gridToRenderable (layout1ToGrid l)

layout1ToGrid :: (Ord x, Ord y) =>
                 Layout1 x y -> Grid (Renderable (Layout1Pick x y))
layout1ToGrid l = aboveN
       [  tval $ layout1TitleToRenderable l
       ,  weights (1,1) $ tval $ gridToRenderable $
              addMarginsToGrid (lm,lm,lm,lm) (layout1PlotAreaToGrid l)
       ,  tval $ layout1LegendsToRenderable l
       ]
  where
    lm = layout1_margin_ l

layout1TitleToRenderable :: (Ord x, Ord y) => Layout1 x y
                                           -> Renderable (Layout1Pick x y)
layout1TitleToRenderable l | null (layout1_title_ l) = emptyRenderable
layout1TitleToRenderable l = addMargins (lm/2,0,0,0)
                                        (mapPickFn L1P_Title title)
  where
    title = label (layout1_title_style_ l) HTA_Centre VTA_Centre
                  (layout1_title_ l)
    lm    = layout1_margin_ l

layout1LegendsToRenderable :: (Ord x, Ord y) =>
                              Layout1 x y -> Renderable (Layout1Pick x y)
layout1LegendsToRenderable l = gridToRenderable g
  where
    g      = besideN [ tval $ mkLegend lefts
                     , weights (1,1) $ tval $ emptyRenderable
                     , tval $ mkLegend rights ]
    lefts  = concat [ plot_legend_ p | (Left p ) <- (layout1_plots_ l) ]
    rights = concat [ plot_legend_ p | (Right p) <- (layout1_plots_ l) ]

    lm     = layout1_margin_ l

    mkLegend vals = case (layout1_legend_ l) of
        Nothing -> emptyRenderable
        Just ls ->  case filter ((/="").fst) vals of
            []  -> emptyRenderable ;
            lvs -> addMargins (0,lm,lm,lm) $
                       mapPickFn L1P_Legend $
                                 legendToRenderable (Legend ls lvs)

layout1PlotAreaToGrid :: (Ord x, Ord y) =>
                          Layout1 x y -> Grid (Renderable (Layout1Pick x y))
layout1PlotAreaToGrid l = layer2 `overlay` layer1
  where
    layer1 = aboveN
         [ besideN [er,     er,    er   ]
         , besideN [er,     er,    er   ]
         , besideN [er,     er,    weights (1,1) plots ]
         ]

    layer2 = aboveN
         [ besideN [er,     er,    ttitle, er,    er       ]
         , besideN [er,     tl,    taxis,  tr,    er       ]
         , besideN [ltitle, laxis, er,     raxis, rtitle   ]
         , besideN [er,     bl,    baxis,  br,    er       ]
         , besideN [er,     er,    btitle, er,    er       ]
         ]

    ttitle = atitle HTA_Centre VTA_Bottom   0 layout1_top_axis_    L1P_TopAxisTitle
    btitle = atitle HTA_Centre VTA_Top      0 layout1_bottom_axis_ L1P_BottomAxisTitle
    ltitle = atitle HTA_Right  VTA_Centre 270 layout1_left_axis_   L1P_LeftAxisTitle
    rtitle = atitle HTA_Left   VTA_Centre 270 layout1_right_axis_  L1P_RightAxisTitle

    er = tval $ emptyRenderable

    atitle ha va rot af pf = if ttext == "" then er
                             else tval $ mapPickFn pf
                                       $ rlabel tstyle ha va rot ttext
      where
        tstyle = laxis_title_style_ (af l)
        ttext  = laxis_title_       (af l)

    plots = tval $ mfill (layout1_plot_background_ l) $ plotsToRenderable l
      where
        mfill Nothing   = id
        mfill (Just fs) = fillBackground fs

    (ba,la,ta,ra) = getAxes l
    baxis = tval $ maybe emptyRenderable
                         (mapPickFn L1P_BottomAxis . axisToRenderable) ba
    taxis = tval $ maybe emptyRenderable
                         (mapPickFn L1P_TopAxis .    axisToRenderable) ta
    laxis = tval $ maybe emptyRenderable
                         (mapPickFn L1P_LeftAxis .   axisToRenderable) la
    raxis = tval $ maybe emptyRenderable
                         (mapPickFn L1P_RightAxis .  axisToRenderable) ra

    tl = tval $ axesSpacer fst ta fst la
    bl = tval $ axesSpacer fst ba snd la
    tr = tval $ axesSpacer snd ta fst ra
    br = tval $ axesSpacer snd ba snd ra

plotsToRenderable :: Layout1 x y -> Renderable (Layout1Pick x y)
plotsToRenderable l = Renderable {
        minsize = return (0,0),
        render  = renderPlots l
    }

renderPlots :: Layout1 x y -> RectSize -> CRender (PickFn (Layout1Pick x y))
renderPlots l sz@(w,h) = do
    when (not (layout1_grid_last_ l)) renderGrids
    preserveCState $ do
        -- render the plots
        setClipRegion (Point 0 0) (Point w h)
        mapM_ rPlot (layout1_plots_ l)
    when (layout1_grid_last_ l) renderGrids
    return pickfn

  where
    (bAxis,lAxis,tAxis,rAxis) = getAxes l

    rPlot (Left  p) = rPlot1 bAxis lAxis p
    rPlot (Right p) = rPlot1 bAxis rAxis p

    xr = (0, w)
    yr = (h, 0)
    reverse rev (a,b) = if rev then (b,a) else (a,b)

    rPlot1 (Just (AxisT _ xs xrev xaxis)) (Just (AxisT _ ys yrev yaxis)) p =
      let 
          xr1 = reverse xrev xr
          yr1 = reverse yrev yr
          yrange = if yrev then (0, h) else (h, 0)
          pmfn (x,y) = Point (mapv xr1 (axis_viewport_ xaxis xr1) x)
                             (mapv yr1 (axis_viewport_ yaxis yr1) y)
          mapv (min,max) _ LMin       = min
          mapv (min,max) _ LMax       = max
          mapv _         f (LValue v) = f v
	  in plot_render_ p pmfn
    rPlot1 _ _ _ = return ()

    pickfn (Point x y) = do  -- Maybe monad
        xat <- mxat
        (yat1,yat2) <- myats
        return (L1P_PlotArea (mapx xat x) (mapy yat1 y)  (mapy yat2 y))
      where
        mxat = case (bAxis,tAxis) of
            (Just at,_)       -> Just at
            (_,Just at)       -> Just at
            (Nothing,Nothing) -> Nothing
        myats = case (lAxis,rAxis) of
            (Just at,Nothing)   -> Just (at,at)
            (Nothing,Just at)   -> Just (at,at)
            (Just at1,Just at2) -> Just (at1,at2)
            (Nothing,Nothing)   -> Nothing
        mapx (AxisT _ _ rev ad) x = axis_tropweiv_ ad (reverse rev xr) x
        mapy (AxisT _ _ rev ad) y = axis_tropweiv_ ad (reverse rev yr) y

    renderGrids = do
      maybeM () (renderAxisGrid sz) tAxis
      maybeM () (renderAxisGrid sz) bAxis
      maybeM () (renderAxisGrid sz) lAxis
      maybeM () (renderAxisGrid sz) rAxis

axesSpacer f1 a1 f2 a2 = embedRenderable $ do
    oh1 <- maybeM (0,0) axisOverhang a1
    oh2 <- maybeM (0,0) axisOverhang a2
    return (spacer (f1 oh1, f2 oh2))

getAxes :: Layout1 x y ->
           (Maybe (AxisT x), Maybe (AxisT y), Maybe (AxisT x), Maybe (AxisT y))
getAxes l = (bAxis,lAxis,tAxis,rAxis)
  where
    (xvals0,xvals1,yvals0,yvals1) = allPlottedValues (layout1_plots_ l)
    xvals                         = xvals0 ++ xvals1
    (yvals0',yvals1')             = layout1_yaxes_control_ l (yvals0,yvals1)

    bAxis = mkAxis E_Bottom (layout1_bottom_axis_ l) xvals
    tAxis = mkAxis E_Top    (layout1_top_axis_ l)    xvals
    lAxis = mkAxis E_Left   (layout1_left_axis_ l)  yvals0'
    rAxis = mkAxis E_Right  (layout1_right_axis_ l) yvals1'

    mkAxis t laxis vals = case laxis_visible_ laxis vals of
        False -> Nothing
        True  -> Just (AxisT t style rev adata)
      where
        style = laxis_style_ laxis
        rev   = laxis_reverse_ laxis
        adata = (laxis_override_ laxis) (laxis_generate_ laxis vals)

allPlottedValues :: [(Either (Plot x y) (Plot x' y'))]
                    -> ( [x], [x'], [y], [y'] )
allPlottedValues plots = (xvals0,xvals1,yvals0,yvals1)
  where
    xvals0 = [ x | (Left p)  <- plots, x <- fst $ plot_all_points_ p]
    yvals0 = [ y | (Left p)  <- plots, y <- snd $ plot_all_points_ p]
    xvals1 = [ x | (Right p) <- plots, x <- fst $ plot_all_points_ p]
    yvals1 = [ y | (Right p) <- plots, y <- snd $ plot_all_points_ p]

defaultLayout1 :: (PlotValue x,PlotValue y) => Layout1 x y
defaultLayout1 = Layout1 {
    layout1_background_      = solidFillStyle $ opaque white,
    layout1_plot_background_ = Nothing,

    layout1_title_           = "",
    layout1_title_style_     = defaultFontStyle{font_size_   =15
                                               ,font_weight_ =C.FontWeightBold},

    layout1_top_axis_        = defaultLayoutAxis {laxis_visible_ = const False},
    layout1_bottom_axis_     = defaultLayoutAxis,
    layout1_left_axis_       = defaultLayoutAxis,
    layout1_right_axis_      = defaultLayoutAxis,

    layout1_yaxes_control_   = id,

    layout1_margin_          = 10,
    layout1_plots_           = [],
    layout1_legend_          = Just defaultLegendStyle,
    layout1_grid_last_       = False
}

defaultLayoutAxis :: PlotValue t => LayoutAxis t
defaultLayoutAxis = LayoutAxis {
   laxis_title_style_ = defaultFontStyle{font_size_=10},
   laxis_title_       = "",
   laxis_style_       = defaultAxisStyle,
   laxis_visible_     = not.null,
   laxis_generate_    = autoAxis,
   laxis_override_    = id,
   laxis_reverse_     = False
}

----------------------------------------------------------------------
-- Template haskell to derive an instance of Data.Accessor.Accessor
-- for each field.
$( deriveAccessors ''Layout1 )
$( deriveAccessors ''LayoutAxis )

-- | Helper to update all axis styles on a Layout1 simultaneously.
updateAllAxesStyles :: (AxisStyle -> AxisStyle) -> Layout1 x y -> Layout1 x y
updateAllAxesStyles uf = (layout1_top_axis    .> laxis_style ^: uf) .
                         (layout1_bottom_axis .> laxis_style ^: uf) .
                         (layout1_left_axis   .> laxis_style ^: uf) .
                         (layout1_right_axis  .> laxis_style ^: uf)

-- | Helper to set the forground color uniformly on a Layout1.
setLayout1Foreground :: AlphaColour Double -> Layout1 x y -> Layout1 x y
setLayout1Foreground fg =
    updateAllAxesStyles  ( (axis_line_style  .> line_color ^= fg)
                         . (axis_label_style .> font_color ^= fg))
    . (layout1_title_style .> font_color ^= fg)
    . (layout1_legend ^: fmap (legend_label_style .> font_color ^= fg))


linkAxes :: ([a], [a]) -> ([a], [a])
linkAxes        (ys1,ys2) = (ys1++ys2,ys1++ys2)

independentAxes :: (a, b) -> (a, b)
independentAxes (ys1,ys2) = (ys1,ys2)
