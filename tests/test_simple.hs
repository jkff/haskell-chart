#!/usr/bin/runhaskell -O0

import Graphics.Rendering.Chart
import Graphics.Rendering.Chart.Simple
import Graphics.Rendering.Chart.Gtk

main = do let xs = [0,0.1..1] :: [Double]
          let pp :: Layout1
              pp = plot xs sin "foobar" cos "o" (sin.sin.cos) "." id "- " (const 0.5)
                   [0.1,0.7,0.5::Double] Dashed
          plotWindow xs sin
          plotPDF "test_simple.pdf" xs sin (cos.sin) "."
          plotPS "test_simple.ps" xs sin (sin.cos) "- "
          renderableToWindow (toRenderable pp) 640 480
          renderableToPDFFile (toRenderable pp) 640 480 "test.pdf"
          renderableToPSFile (toRenderable pp) 640 480 "test.ps"