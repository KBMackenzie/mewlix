{-# LANGUAGE OverloadedStrings #-}

module Meowscript.Core.Keys
( keyLookup 
, keyAsRef
, assignment
, pairAsRef
, pairAsInsert
, ensureValue
, assignNew
, extractKey
, ensureKey
, ensureLocal
) where

import Meowscript.Core.AST
import Meowscript.Core.Environment
import qualified Data.Text as Text
import Meowscript.Core.Exceptions
import Meowscript.Utils.Show
import Control.Monad.Except (throwError)
--import qualified Data.Map.Strict as Map

keyLookup :: KeyType -> Evaluator Prim
{-# INLINE keyLookup #-}
keyLookup key = case key of
    (KeyModify x) -> lookUp x
    (KeyNew x) -> lookUp x
    (KeyRef x) -> pairAsRef x >>= readMeowRef

keyAsRef :: KeyType -> Evaluator PrimRef
{-# INLINE keyAsRef #-}
keyAsRef key = case key of
    (KeyModify x) -> lookUpRef x
    (KeyNew x) -> lookUpRef x
    (KeyRef x) -> pairAsRef x

assignment :: KeyType -> Prim -> Evaluator ()
{-# INLINE assignment #-}
assignment key value = case key of
    (KeyModify x) -> insertVar x value False
    (KeyNew x) -> insertVar x value True
    (KeyRef x) -> pairAsInsert x value

pairAsRef :: (PrimRef, Prim) -> Evaluator PrimRef
{-# INLINE pairAsRef #-}
pairAsRef (ref, prim) = (,) <$> ensureKey prim <*> readMeowRef ref >>= uncurry peekAsObject

pairAsInsert :: (PrimRef, Prim) -> Prim -> Evaluator ()
{-# INLINE pairAsInsert #-}
pairAsInsert (ref, prim) value = ensureKey prim >>= flip (insertObject ref) value

ensureValue :: Prim -> Evaluator Prim
{-# INLINABLE ensureValue #-}
ensureValue (MeowKey key) = keyLookup key >>= ensureValue
ensureValue x = return x

assignNew :: Key -> Prim -> Evaluator ()
{-# INLINE assignNew #-}
assignNew key value = insertVar key value True

extractKey :: KeyType -> Evaluator Text.Text
extractKey (KeyModify x) = return x
extractKey (KeyNew x) = return x
extractKey x = throwError $ meowUnexpected "Cannot extract reference as key!" (showT x)

ensureKey :: Prim -> Evaluator Text.Text
ensureKey (MeowKey key) = extractKey key
ensureKey x = throwError =<< notKey [x]

ensureLocal :: KeyType -> KeyType
{-# INLINE ensureLocal #-}
ensureLocal (KeyModify x) = KeyNew x
ensureLocal x = x
