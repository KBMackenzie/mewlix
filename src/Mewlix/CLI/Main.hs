{-# LANGUAGE LambdaCase #-}

module Mewlix.CLI.Main 
( run
) where

import Mewlix.CLI.Data (MewlixOptions(..), runCLI)
import Mewlix.CLI.Process (runClean, runBuild)

run :: IO ()
run = runCLI >>= \case
    (Build paths)   -> runBuild paths
    Clean           -> runClean