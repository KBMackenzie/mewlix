{-# LANGUAGE OverloadedStrings #-} 
{-# LANGUAGE LambdaCase #-}

module Meowscript.Core.Base
( baseLibrary
) where

import Meowscript.Core.AST
import Meowscript.Core.Exceptions
import Meowscript.Core.Environment
import Meowscript.Core.Keys
import Meowscript.Core.Pretty
import Meowscript.Utils.IO
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Data.List as List
import qualified Data.Text.IO as TextIO
import qualified Data.Text.Read as Read
import Control.Monad.Except(throwError)
import Control.Monad.State(liftIO)
import Data.Functor((<&>))
import Control.Monad((>=>))

baseLibrary :: IO ObjectMap
baseLibrary = createObject
    [ ("meow"    , MeowIFunc  ["x"] meow      )
    , ("listen"  , MeowIFunc  [   ] listen    )
    , ("reverse" , MeowIFunc  ["x"] reverseFn )
    , ("sort"    , MeowIFunc  ["x"] sortFn    )
    , ("int"     , MeowIFunc  ["x"] toInt     )
    , ("float"   , MeowIFunc  ["x"] toDouble  )
    , ("string"  , MeowIFunc  ["x"] toString  )
    , ("taste"   , MeowIFunc  ["x"] toBool    )
    , ("keys"    , MeowIFunc  ["x"] getKeys   )
    , ("values"  , MeowIFunc  ["x"] getValues )
    , ("type_of" , MeowIFunc  ["x"] typeOf    )
    , ("throw"   , MeowIFunc  ["x"] throwEx   )
    -- File IO --
    , ("read_file"   , MeowIFunc ["path"]             meowRead   )
    , ("write_file"  , MeowIFunc ["path", "contents"] meowWrite  )
    , ("append_file" , MeowIFunc ["path", "contents"] meowAppend )]

{- IO -} 
----------------------------------------------------------
meow :: Evaluator Prim
meow = lookUp "x" >>= showMeow >>= (liftIO . printStrLn) >> return MeowLonely

listen :: Evaluator Prim
listen = liftIO TextIO.getLine <&> MeowString

{- Lists/Strings -}
----------------------------------------------------------
reverseFn :: Evaluator Prim
reverseFn = lookUp "x" >>= \case
    (MeowList x) -> (return . MeowList . reverse) x
    (MeowString x) -> (return . MeowString . Text.reverse) x
    x -> throwError =<< badArgs "reverse" [x]

sortFn :: Evaluator Prim
sortFn = lookUp "x" >>= \case
    (MeowList x) -> (return . MeowList . List.sort) x
    x -> throwError =<< badArgs "sort" [x]

{- Conversion -}
----------------------------------------------------------

toString :: Evaluator Prim
toString = lookUp "x" >>= showMeow <&> MeowString

toInt :: Evaluator Prim
toInt = lookUp "x" >>= \case
    a@(MeowInt _) -> return a
    (MeowDouble x) -> (return . MeowInt . floor) x
    (MeowString x) -> MeowInt <$> readInt x
    (MeowBool x) -> (return . MeowInt . fromEnum) x
    x -> throwError =<< badArgs "int" [x]

readInt :: Text.Text -> Evaluator Int
readInt txt = case Read.signed Read.decimal txt of
    (Left er) -> throwError =<< badValue "int" (Text.pack er) [MeowString txt]
    (Right x) -> (return . fst) x

toDouble :: Evaluator Prim
toDouble = lookUp "x" >>= \case
    a@(MeowDouble _) -> return a
    (MeowInt x) -> (return . MeowDouble . fromIntegral) x
    (MeowString x) -> MeowDouble <$> readDouble x
    (MeowBool x) -> (return . MeowDouble . fromIntegral . fromEnum) x
    x -> throwError =<< badArgs "float" [x]

readDouble :: Text.Text -> Evaluator Double
readDouble txt = case Read.signed Read.double txt of
    (Left er) -> throwError =<< badValue "float" (Text.pack er) [MeowString txt]
    (Right x) -> (return . fst) x

toBool :: Evaluator Prim
toBool = lookUp "x" <&> (MeowBool . meowBool)

{- Boxes -}
----------------------------------------------------------

getKeys :: Evaluator Prim
getKeys = lookUp "x" >>= \case
    (MeowObject x) -> (return . MeowList) (MeowString <$> Map.keys x)
    x -> throwError =<< badArgs "keys" [x]

getValues :: Evaluator Prim
getValues = lookUp "x" >>= \case
    (MeowObject x) -> MeowList <$> mapM (evalRef >=> ensureValue) (Map.elems x)
    x -> throwError =<< badArgs "values" [x]

{- Reflection -}
----------------------------------------------------------

typeOf :: Evaluator Prim
typeOf = lookUp "x" >>= \x -> return . MeowString $ case x of
    (MeowString _)  -> "string"
    (MeowInt _)     -> "int"
    (MeowDouble _)  -> "float"
    (MeowBool _)    -> "bool"
    (MeowList _)    -> "list"
    (MeowObject _)  -> "object"
    (MeowFunc {})   -> "function"
    (MeowIFunc {})  -> "inner-function"
    MeowLonely      -> "lonely"
    (MeowKey _)     -> "key" -- This shouldn't be evaluated, but alas.


{- Exceptions -}
----------------------------------------------------------
-- Allow users to throw their own exceptions.
-- This is shown a special exception, 'CatOnComputerException'.

throwEx :: Evaluator Prim
throwEx = lookUp "x" >>= \case
    (MeowString x) -> throwError (catOnComputer x)
    x -> throwError =<< badArgs "throw" [x]


{- File IO -}
----------------------------------------------------------

meowRead :: Evaluator Prim
meowRead = lookUp "path" >>= \case
    (MeowString path) -> (liftIO . safeReadFile . Text.unpack) path >>= \case
        (Left exception) -> throwError (badFile path "read_file" exception)
        (Right contents) -> (return . MeowString) contents
    x -> throwError =<< badArgs "read_file" [x]

meowWrite :: Evaluator Prim
meowWrite = (,) <$> lookUp "path" <*> lookUp "contents" >>= \case
    (MeowString path, MeowString contents) ->
        liftIO (safeWriteFile (Text.unpack path) contents) >>= \case
            (Left exception) -> throwError (badFile path  "write_file" exception)
            (Right _) -> (return . MeowString) contents
    (x, y) -> throwError =<< badArgs "write_file" [x, y]

meowAppend :: Evaluator Prim
meowAppend = (,) <$> lookUp "path" <*> lookUp "contents" >>= \case
    (MeowString path, MeowString contents) ->
        liftIO (safeAppendFile (Text.unpack path) contents) >>= \case
            (Left exception) -> throwError (badFile path  "append_file" exception)
            (Right _) -> (return . MeowString) contents
    (x, y) -> throwError =<< badArgs "append_file" [x, y]
