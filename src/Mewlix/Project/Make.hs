{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Mewlix.Project.Make
( ProjectContext(..)
, ProjectMaker(..)
, make
, makeJS
-- Re-exports:
, liftIO
, asks
, throwError
, catchError
) where

import Mewlix.Compiler (CompilerFunc, compileJS)
import Control.Monad.Reader (ReaderT, MonadReader, asks, runReaderT)
import Control.Monad.Except (ExceptT, MonadError(throwError, catchError), runExceptT)
import Control.Monad.IO.Class (MonadIO(liftIO))

data ProjectContext = ProjectContext
    { projectCompiler  :: CompilerFunc
    , projectExtension :: String       }

newtype ProjectMaker a = ProjectMaker
    { runProjectMaker :: ReaderT ProjectContext (ExceptT String IO) a }
    deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadError String
             , MonadReader ProjectContext
             )

make :: ProjectContext -> ProjectMaker a -> IO (Either String a)
make ctx = runExceptT . flip runReaderT ctx . runProjectMaker

makeJS :: ProjectMaker a -> IO (Either String a)
makeJS = make ProjectContext
    { projectCompiler  = compileJS
    , projectExtension = "js"      }
