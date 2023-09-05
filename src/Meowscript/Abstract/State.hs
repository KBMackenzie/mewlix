{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Meowscript.Abstract.State
( Environment(..)
, Module(..)
, ModuleCache(..)
, EvaluatorMeta(..)
, ModuleInfo(..)
, EvaluatorState(..)
, MeowFlag(..)
, DefineMap
, FlagSet
, CacheMap
, Libraries(..)
-- Lenses:
, cachedModulesL
, defineMapL
, includePathsL
, flagSetL
, moduleSocketL
, modulePathL
, moduleIsMainL
, evaluatorEnvL
, moduleInfoL
, evaluatorMetaL
, evaluatorLibsL
, getModuleL
, getCacheL
-- Setters:
, addDefine
, addFlag
, addInclude
, addLibrary
-- Utils:
, joinLibraries
, createEnvironment
-- Inititializers:
--, initMeta
--, emptyMeta
--, initState
) where

-- Meow:
import Meowscript.Data.Ref
import Meowscript.Parser.AST
-- Types:
import Data.Set (Set)
import Data.Text (Text)
import Meowscript.Data.Stack (Stack)
import Data.HashMap.Strict (HashMap)
-- Qualified:
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.HashMap.Strict as HashMap
import qualified Meowscript.Data.Stack as Stack
-- Other:
import Lens.Micro.Platform (makeLensesFor, (^.), (%~), over)
import Control.Monad.IO.Class (MonadIO(..))

newtype Environment a = Environment { getEnv :: HashMap Text (Ref a) }
    deriving (Semigroup)

newtype Module = Module { getModule :: Block }
newtype ModuleCache = ModuleCache { getCache :: Ref CacheMap }

data EvaluatorMeta = EvaluatorMeta
    { cachedModules :: ModuleCache
    , defineMap     :: DefineMap
    , includePaths  :: [FilePath]
    , flagSet       :: FlagSet
    , moduleSocket  :: Maybe Int   }

data ModuleInfo = ModuleInfo
    { modulePath    :: FilePath
    , moduleIsMain  :: Bool        }

newtype Libraries p = Libraries
    { getLibs :: Stack (Environment p) }

data EvaluatorState p = EvaluatorState
    { evaluatorEnv  :: Ref (Environment p)
    , moduleInfo    :: ModuleInfo
    , evaluatorMeta :: EvaluatorMeta
    , evaluatorLibs :: Libraries p        }

{- Flags -}
-------------------------------------------------------------------------------------
data MeowFlag =
      ImplicitMain
    | FullScreen
    deriving (Eq, Ord, Show, Enum, Bounded)

{- Aliases -}
-------------------------------------------------------------------------------------
type DefineMap = HashMap Text Text
type FlagSet   = Set MeowFlag
type CacheMap  = HashMap FilePath Module

{- Lenses -}
-------------------------------------------------------------------------------------
$(makeLensesFor
    [ ("cachedModules", "cachedModulesL")
    , ("defineMap"    , "defineMapL"    )
    , ("includePaths" , "includePathsL" )
    , ("flagSet"      , "flagSetL"      )
    , ("moduleSocket" , "moduleSocketL" ) ] ''EvaluatorMeta)

$(makeLensesFor
    [ ("modulePath"   , "modulePathL"   )
    , ("moduleIsMain" , "moduleIsMainL" ) ] ''ModuleInfo)

$(makeLensesFor
    [ ("evaluatorEnv" , "evaluatorEnvL" )
    , ("moduleInfo"   , "moduleInfoL"   )
    , ("evaluatorMeta", "evaluatorMetaL")
    , ("evaluatorLibs", "evaluatorLibsL") ] ''EvaluatorState)

$(makeLensesFor
    [ ("getModule"    , "getModuleL"    ) ] ''Module)

$(makeLensesFor
    [ ("getCache"     , "getCacheL"     ) ] ''ModuleCache)

$(makeLensesFor
    [ ("getLibs"      , "getLibsL"      ) ] ''Libraries)

{- Setters -}
-------------------------------------------------------------------------------------
addDefine :: Text -> Text -> EvaluatorState p -> EvaluatorState p
addDefine key item = (evaluatorMetaL.defineMapL) %~ HashMap.insert key item

addFlag :: MeowFlag -> EvaluatorState p -> EvaluatorState p
addFlag = over (evaluatorMetaL.flagSetL) . Set.insert

addInclude :: FilePath -> EvaluatorState p -> EvaluatorState p
addInclude = over (evaluatorMetaL.includePathsL) . (:)

addLibrary :: Environment p -> EvaluatorState p -> EvaluatorState p
addLibrary = over (evaluatorLibsL.getLibsL) . Stack.push

{- Utils -}
-------------------------------------------------------------------------------------
joinLibraries :: Libraries p -> Environment p
joinLibraries = foldr (<>) emptyEnv . getLibs
    where emptyEnv = Environment HashMap.empty

createEnvironment :: (MonadIO m) => [(Text, a)] -> m (Environment a)
createEnvironment pairs = do
    let pack (key, ref) = (key,) <$> newRef ref
    Environment . HashMap.fromList <$> mapM pack pairs


{- Initializers -}
-------------------------------------------------------------------------------------
{-
initMeta :: (MonadIO m) => DefineMap -> [FilePath] -> FlagSet -> m EvaluatorMeta
initMeta defmap include flagset = do
    moduleCache <- ModuleCache <$> newRef HashMap.empty
    return EvaluatorMeta {
        cachedModules   = moduleCache,
        defineMap       = defmap,
        includePaths    = include,
        flagSet         = flagset,
        moduleSocket    = Nothing
    }

emptyMeta :: (MonadIO m) => m EvaluatorMeta
emptyMeta = initMeta HashMap.empty [] Set.empty

initState :: (MonadIO m) => FilePath -> Bool -> m (EvaluatorState p)
initState path isMain = do
    ctx     <- initContext 
    meta    <- emptyMeta
    let info = ModuleInfo {
        modulePath   = path,
        moduleIsMain = isMain
    }
    let libs = Libraries {
        getLibs = Stack.empty
    }
    return EvaluatorState {
        evaluatorEnv  = ctx,
        moduleInfo    = info,
        evaluatorMeta = meta,
        evaluatorLibs = libs
    }
-}

{-
-- Creates state with a clean context; everything else is unchanged.
-- This function does not affect context.
cleanContext :: (MonadIO m) => EvaluatorState p -> m (EvaluatorState p)
cleanContext state = do
    let libs = joinLibraries (evaluatorLibs state)
    !newCtx <- initContext
    modifyRef (<> libs) (globalEnv newCtx)
    return state { evaluatorEnv = newCtx }
-}