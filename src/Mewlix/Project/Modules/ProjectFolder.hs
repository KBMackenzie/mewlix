module Mewlix.Project.Modules.ProjectFolder
( projectFolder
, toOutputPath
, makeProjectFolder
, preparePath
) where

import Mewlix.Project.Make (ProjectMaker, ProjectContext(..), asks, liftIO, langExtension)
import Control.Monad.IO.Class (MonadIO)
import System.FilePath ((</>), takeDirectory, isAbsolute, dropDrive, replaceExtension)
import System.Directory (getCurrentDirectory, createDirectoryIfMissing)

projectFolder :: (MonadIO m) => m FilePath
projectFolder = (</> "mewlix-output/mewlix/user/") <$> liftIO getCurrentDirectory 

toOutputPath :: FilePath -> ProjectMaker FilePath
toOutputPath inputPath = do
    extension <- langExtension <$> asks projectLanguage

    let handleAbsolute :: FilePath -> FilePath
        handleAbsolute path = if isAbsolute path then dropDrive path else path
    
    let handleExtension :: FilePath -> FilePath
        handleExtension = replaceExtension extension

    let appendPath = flip (</>) . handleExtension . handleAbsolute
    appendPath inputPath <$> projectFolder

preparePath :: (MonadIO m) => FilePath -> m ()
preparePath = liftIO . createDirectoryIfMissing True . takeDirectory

makeProjectFolder :: (MonadIO m) => m ()
makeProjectFolder = liftIO . createDirectoryIfMissing True =<< projectFolder
