{-# LANGUAGE OverloadedStrings #-}

{- This module re-exports the Primitive constructor
 - and core functions. -}

module Meowscript
( runBasic
, Prim(..)
) where

import Meowscript.Core.AST
import Meowscript.Core.RunEvaluator
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Control.StopWatch (stopWatch)

runBasic :: FilePath -> IO ()
runBasic path = do
    (output, time) <- stopWatch $ runMeow' path
    case output of
        (Right x) -> print time >> print x
        (Left x) -> TextIO.putStrLn x
