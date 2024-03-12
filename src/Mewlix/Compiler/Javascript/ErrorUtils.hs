{-# LANGUAGE OverloadedStrings #-}

module Mewlix.Compiler.Javascript.ErrorUtils
( ErrorCode(..)
, errorInfo
, createError
) where

import Data.Text (Text)
import Mewlix.String.Escape (escapeString)
import Mewlix.String.Utils (quotes, parens)
import Mewlix.Compiler.Javascript.Constants (mewlix)
import Mewlix.Utils.Show (showT)
import Text.Megaparsec.Pos (SourcePos(..), unPos)

data ErrorCode =
      TypeMisMatch
    | DivideByZero
    | BadConversion
    | CatOnComputer
    | Console
    | Graphic
    | InvalidImport
    | CriticalError
    | ExternalError
    deriving (Eq, Ord, Show, Read, Enum, Bounded)

mewlixError :: Text
mewlixError = mewlix "MewlixError"

errorCode :: ErrorCode -> Text
errorCode = (mewlix "ErrorCode." <>) . showT

errorInfo :: SourcePos -> Text
errorInfo pos = (quotes. escapeString . mconcat)
    [ "\n -> In module "
    , (showT . sourceName) pos
    , ", at line "
    , (showT . unPos . sourceLine) pos ]     

createError :: ErrorCode -> SourcePos -> Text -> Text
createError code pos expr = do
    let message :: Text
        message = mconcat [ parens expr, " + ", errorInfo pos ]

    let arguments :: Text
        arguments = parens (errorCode code <> message)

    parens ("await (async () => { throw new " <> mewlixError <> arguments <> " })()")
