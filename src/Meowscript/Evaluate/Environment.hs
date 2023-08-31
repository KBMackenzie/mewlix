{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FunctionalDependencies #-}

module Meowscript.Evaluate.Environment
( Environment(..)
, Context(..)
, MeowEnvironment(..)
, contextSearch
, contextWrite
, localContext
, contextDefine
, contextMany
, initContext
, freezeLocal
) where

import Meowscript.Data.Key
import Meowscript.Data.Ref
import Meowscript.Evaluate.Exception
import Meowscript.Evaluate.MeowThrower
import qualified Data.Text as Text
import qualified Data.HashMap.Strict as HashMap
import Control.Monad.IO.Class (MonadIO(..))

newtype Environment a = Environment
    { getEnv :: HashMap.HashMap Key (Ref a) }

data Context a = Context
    { globalEnv    :: Ref (Environment a) 
    , currentEnv   :: Ref (Environment a)
    , enclosingCtx :: Maybe (Context a)  }

class (Monad m, MonadIO m) => MeowEnvironment s m | m -> s where
    lookUpRef  :: Key -> m (Maybe (Ref s))
    contextGet :: (Context s -> a) -> m a
    contextSet :: (Context s -> Context s) -> m ()
    runLocal   :: m a -> Context s -> m a

    context :: m (Context s)
    context = contextGet id

    lookUp :: (MeowThrower m) => Key -> m s
    lookUp key = do
        x <- lookUpRef key
        case x of
            (Just !ref) -> readRef ref
            Nothing     -> throwException CatException {
                exceptionType = MeowUnboundKey,
                exceptionMessage = Text.concat [ "Unbound key: \"", key, "\"!" ]
            }

-----------------------------------------------------------------------------

contextSearch :: (MonadIO m) => Key -> Context a -> m (Maybe (Ref a))
contextSearch !key !ctx = (readRef . currentEnv) ctx >>= \envref ->
    case (HashMap.lookup key . getEnv) envref of
    (Just !ref) -> return (Just ref)
    Nothing     -> case enclosingCtx ctx of
        (Just enclosing) -> contextSearch key enclosing
        Nothing          -> return Nothing

contextWrite :: (MonadIO m) => Key -> a -> Context a -> m ()
contextWrite !key !value !ctx = do
    let !env = currentEnv ctx
    !valueRef <- newRef value
    let f = Environment . HashMap.insert key valueRef . getEnv
    modifyRef f env

localContext :: (MonadIO m) => Context a -> m (Context a)
localContext !ctx = do
    newEnv <- newRef $ Environment HashMap.empty
    let !newCtx = Context {
        globalEnv = globalEnv ctx,
        currentEnv = newEnv,
        enclosingCtx = Just ctx
    }
    return newCtx

contextDefine :: (MonadIO m) => Key -> Ref a -> Context a -> m ()
contextDefine !key !ref !ctx = do
    let !env = currentEnv ctx
    let f = Environment . HashMap.insert key ref . getEnv
    modifyRef f env

contextMany :: (MonadIO m) => [(Key, Ref a)] -> Context a -> m ()
contextMany pairs ctx = do
    let !env = currentEnv ctx
    let bind (key, ref) = HashMap.insert key ref
    let makeMap = Environment . (\hashmap -> foldr bind hashmap pairs) . getEnv
    modifyRef makeMap env

initContext :: (MonadIO m) => m (Context a)
initContext = do
    !initial <- newRef $ Environment HashMap.empty
    let !ctx = Context {
        globalEnv = initial,
        currentEnv = initial,
        enclosingCtx = Nothing
    }
    return ctx

-- A helper to copy and freeze the local context
-- for use in lambda closures.
freezeLocal :: (MonadIO m) => Context a -> m (Context a)
freezeLocal ctx = do
    !newLocal <- copyRef $ currentEnv ctx
    return ctx { currentEnv = newLocal }
