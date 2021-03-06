module Test2 where

import Graphics.Rendering.Chart
import Graphics.Rendering.Chart.Layout(layout1ToRenderable)
import Graphics.Rendering.Chart.Grid
import qualified Graphics.UI.Gtk as G
import qualified Graphics.UI.Gtk.Gdk.Events as GE
import qualified Graphics.Rendering.Cairo as C

import Data.Time.LocalTime
import Data.Colour
import Data.Colour.Names
import Data.Colour.SRGB
import Data.Accessor
import Data.IORef
import System.Environment(getArgs)
import Prices(prices2)

type PickType = Layout1Pick LocalTime Double

chart :: [(LocalTime,Double,Double)] -> Bool -> Double -> Renderable PickType
chart prices showMinMax lwidth = layout1ToRenderable layout
  where

    lineStyle c = line_width ^= 3 * lwidth
                $ line_color ^= c
                $ defaultPlotLines ^. plot_lines_style

    limitLineStyle c = line_width ^= lwidth
                $ line_color ^= opaque c
                $ line_dashes ^= [5,10]
                $ defaultPlotLines ^. plot_lines_style

    price1 = plot_lines_style ^= lineStyle (opaque blue)
           $ plot_lines_values ^= [[ (d, v) | (d,v,_) <- prices]]
           $ plot_lines_title ^= "price 1"
           $ defaultPlotLines

    price2 = plot_lines_style ^= lineStyle (opaque green)
	   $ plot_lines_values ^= [[ (d, v) | (d,_,v) <- prices]]
           $ plot_lines_title ^= "price 2"
           $ defaultPlotLines

    (min1,max1) = (minimum [v | (_,v,_) <- prices],maximum [v | (_,v,_) <- prices])
    (min2,max2) = (minimum [v | (_,_,v) <- prices],maximum [v | (_,_,v) <- prices])
    limits | showMinMax = [ Left $ hlinePlot "min/max" (limitLineStyle blue) min1,
                            Left $ hlinePlot "" (limitLineStyle blue) max1,
                            Right $ hlinePlot "min/max" (limitLineStyle green) min2,
                            Right $ hlinePlot "" (limitLineStyle green) max2 ]
           | otherwise  = []

    bg = opaque $ sRGB 0 0 0.25
    fg = opaque white
    fg1 = opaque $ sRGB 0.0 0.0 0.15

    layout = layout1_title ^="Price History"
           $ layout1_background ^= solidFillStyle bg
           $ updateAllAxesStyles (axis_grid_style ^= solidLine 1 fg1)
           $ layout1_left_axis ^: laxis_override ^= axisGridHide
           $ layout1_right_axis ^: laxis_override ^= axisGridHide
           $ layout1_bottom_axis ^: laxis_override ^= axisGridHide
 	   $ layout1_plots ^= ([Left (toPlot price1), Right (toPlot price2)] ++ limits)
           $ layout1_grid_last ^= False
           $ setLayout1Foreground fg
           $ defaultLayout1

updateCanvas :: Renderable a -> G.DrawingArea -> IORef (Maybe (PickFn a)) -> IO Bool
updateCanvas chart canvas pickfv = do
    win <- G.widgetGetDrawWindow canvas
    (width, height) <- G.widgetGetSize canvas
    let sz = (fromIntegral width,fromIntegral height)
    pickf <- G.renderWithDrawable win $ runCRender (render chart sz) bitmapEnv
    writeIORef pickfv (Just pickf)
    return True

createRenderableWindow :: (Show a) => Renderable a -> Int -> Int -> IO G.Window
createRenderableWindow chart windowWidth windowHeight = do
    pickfv <- newIORef Nothing
    window <- G.windowNew
    canvas <- G.drawingAreaNew
    G.widgetSetSizeRequest window windowWidth windowHeight
    G.onExpose canvas $ const (updateCanvas chart canvas pickfv)
    G.onButtonPress canvas $ \(GE.Button{GE.eventX=x,GE.eventY=y}) -> do
        print (x,y)
        (Just pickf) <- readIORef pickfv
        print (pickf (Point x y))
        return True
    G.set window [G.containerChild G.:= canvas]
    return window

chartWindow = do
    window <- createRenderableWindow (chart prices2 True 1.00) 640 480
    G.onDestroy window G.mainQuit
    G.widgetShowAll window
    G.mainGUI

gridWindow = do
    window <- createRenderableWindow (gridToRenderable testgrid) 640 480
    G.onDestroy window G.mainQuit
    G.widgetShowAll window
    G.mainGUI
  where
    testgrid :: Grid (Renderable String)
    testgrid = aboveN
        [ besideN [ f "AAAAA", e, f "BBBBB" ]
        , besideN [ f "CCCCC", e, f "DDDDD" ]
        ]
    f s = tval $ setPickFn (const (Just s)) $ label defaultFontStyle HTA_Centre VTA_Centre s
    e = tval $ spacer (20,20)

                                       
main = do
  G.initGUI
  chartWindow
