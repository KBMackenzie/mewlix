{-# LANGUAGE OverloadedStrings #-}

module Mewlix.Parser.Prim
( parsePrim
, parseString
, parseStringM
, parseKey
, parseName
) where

import Mewlix.Parser.AST
import Mewlix.Parser.Utils
import Mewlix.Parser.Keywords
import Data.Text (Text)
import qualified Data.Text as Text
import Text.Megaparsec ((<?>))
import qualified Data.HashSet as HashSet
import qualified Text.Megaparsec as Mega
import qualified Text.Megaparsec.Char as MChar
import qualified Text.Megaparsec.Char.Lexer as Lexer
import Control.Monad (void, when)
import Data.Char (isAlphaNum, isAscii)

{- Prims: -}
----------------------------------------------------------------
parsePrim :: Parser ParserPrim
parsePrim = Mega.choice
    [ PrimStr   <$> parseString
    , PrimStr   <$> parseStringM
    , PrimFloat <$> parseFloat
    , PrimInt   <$> parseInt
    , PrimBool  <$> parseBool
    , PrimNil   <$  parseNil     ]

{- Escape sequences: -}
----------------------------------------------------------------
escapeChar :: Char -> Char
escapeChar c = case c of
    'n'     -> '\n'
    't'     -> '\t'
    'b'     -> '\b'
    'r'     -> '\r'
    'f'     -> '\f'
    other   -> other

{- Single-line strings: -}
----------------------------------------------------------------
stringChar :: Parser Char
stringChar = Mega.choice
    [ MChar.char '\\' >> fmap escapeChar Mega.anySingle
    , MChar.newline >> fail "Linebreak in string!"
    , Mega.satisfy (/= '"')                             ]

parseString :: Parser Text
parseString = do
    let quotation :: Parser ()
        quotation = (void . MChar.char) '"' <?> "quotation mark"

    quotation
    text <- Text.pack <$> Mega.many stringChar <?> "string"
    lexeme quotation
    return text

{- Multi-line strings: -}
----------------------------------------------------------------
stringCharM :: Parser Char
stringCharM = Mega.choice
    [ MChar.char '\\' >> fmap escapeChar Mega.anySingle
    , Mega.satisfy (/= '"')                             ]

parseStringM :: Parser Text
parseStringM = do
    let quotations :: Parser ()
        quotations = (void . MChar.string) "\"\"\"" <?> "triple quotes"

    quotations
    text <- Text.pack <$> Mega.many stringCharM <?> "multiline string"
    lexeme quotations
    return text

{- Numbers and constants: -}
----------------------------------------------------------------
parseInt :: Parser Int
parseInt = lexeme (Lexer.signed whitespace Lexer.decimal) <?> "int"

parseFloat :: Parser Double
parseFloat = Mega.try (lexeme (Lexer.signed whitespace Lexer.float)) <?> "float"

parseBool :: Parser Bool
parseBool = Mega.choice
    [ True  <$ MChar.string meowTrue
    , False <$ MChar.string meowFalse ] <?> "boolean"

parseNil :: Parser ()
parseNil = (void . MChar.string) meowNil

{- Keys + identifers: -}
----------------------------------------------------------------
{- Allow non-Ascii characters in keys.
 -
 - Language keywords are only gonna use AlphaNumeric characters.
 -
 - Allowing non-Ascii characters lets Unicode characters be identifiers,
 - whilst not conflicting with the language keywords, which only use Ascii characters. -}

isKeyChar :: Char -> Bool
isKeyChar c = isAlphaNum c || c == '_' || (not . isAscii) c

parseKey :: Parser Text
parseKey = lexeme (Mega.takeWhile1P (Just "key") isKeyChar)

{- Parse identifiers (variable names, function names, et cetera).
 - These cannot be reserved keywords. -}
parseName :: Parser Text
parseName = do
    text <- parseKey <?> "identifier"
    when (HashSet.member text reservedKeywords) 
        (fail (Text.unpack text ++ " is a reserved keyword!"))
    return text
