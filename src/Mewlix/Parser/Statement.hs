{-# LANGUAGE OverloadedStrings #-}

module Mewlix.Parser.Statement
( root
, Nesting(..)
) where

import Mewlix.Abstract.AST
    ( Block(..)
    , Primitive(..)
    , Expression(..)
    , Statement(..)
    , MewlixFunction(..)
    , MewlixClass(..)
    , Conditional(..)
    , YarnBall(..),
    )
import Mewlix.Abstract.Key (Key(..))
import Mewlix.Abstract.Module (ModuleData(..))
import Mewlix.Parser.Module (parseModuleKey)
import Mewlix.Parser.Primitive (parseKey, parseParams)
import Mewlix.Parser.Expression (declaration, expression)
import Mewlix.Parser.Utils
    ( Parser
    , linespace
    , multiline
    , symbol
    )
import Mewlix.Parser.Keyword (keyword)
import Mewlix.Keywords.Types (SimpleKeyword(..))
import Data.List.NonEmpty (NonEmpty((:|)))
import qualified Mewlix.Keywords.LanguageKeywords as Keywords
import Text.Megaparsec ((<|>), (<?>))
import qualified Text.Megaparsec as Mega
import Control.Monad (when)
import Data.Maybe (fromMaybe)
import qualified Data.List as List

root :: Parser YarnBall
root = Mega.between linespace Mega.eof yarnBall

yarnBall :: Parser YarnBall
yarnBall = do
    key  <- (<?> "yarn ball") . Mega.optional $ do
        keyword Keywords.yarnball <|> keyword Keywords.yarnball'
        parseModuleKey <* linespace
    body <- Block <$> Mega.many (statement Root)
    return (YarnBall key body)

{- Nesting -}
----------------------------------------------------------------
data Nesting =
      Root
    | Nested
    | NestedInLoop
    deriving (Eq, Ord, Show, Enum, Bounded)

-- The maximum nesting should always propagate.
-- The 'max' function is helpful: Root `max` Nested = Nested

{- Parse statements: -}
----------------------------------------------------------------
statement :: Nesting -> Parser Statement
statement nesting = choose
    [ whileLoop     nesting
    , ifelse        nesting
    , declareVar    nesting
    , funcDef       nesting
    , returnKey     nesting
    , assert        nesting
    , continueKey   nesting
    , breakKey      nesting
    , importKey     nesting
    , importList    nesting
    , forEach       nesting
    , classDef      nesting
    , tryCatch      nesting
    , expressionStm nesting ]
    <?> "statement"
    where choose = Mega.choice . map multiline

block :: Nesting -> Maybe (Parser ()) -> Parser Block
block nesting customStop = do
    let stopPoint = fromMaybe (keyword Keywords.end) customStop
    fmap Block . Mega.many $ do
        Mega.notFollowedBy stopPoint
        statement nesting

open :: Parser a -> Parser a
open = (<* linespace)

close :: Parser ()
close = Mega.choice
    [ keyword Keywords.end
    , fail "possibly unclosed block" ]


{- Expression -}
----------------------------------------------------------------
expressionStm :: Nesting -> Parser Statement
expressionStm  _ = ExpressionStatement <$> expression


{- Declaration -}
----------------------------------------------------------------
declareVar :: Nesting -> Parser Statement
declareVar nesting = do
    let bind = if nesting == Root then Binding else LocalBinding
    uncurry bind <$> declaration


{- While -}
----------------------------------------------------------------
whileLoop :: Nesting -> Parser Statement
whileLoop nesting = do
    condition <- open $ do
        keyword Keywords.while
        expression
    body <- block (max nesting NestedInLoop) Nothing
    close
    return (WhileLoop condition body)


{- If Else -}
----------------------------------------------------------------
ifelse :: Nesting -> Parser Statement
ifelse nesting = do
    let nest = max nesting Nested
    let stopPoint = Mega.choice
            [ keyword Keywords.elif
            , keyword Keywords.else_
            , keyword Keywords.end  ]

    initialConditional <- do
        condition <- open $ do
            keyword Keywords.if_
            expression
        body      <- block nest (Just stopPoint)
        return (Conditional condition body)

    additonalConditionals <- Mega.many $ do
        condition <- open $ do
            keyword Keywords.elif
            expression
        body      <- block nest (Just stopPoint)
        return (Conditional condition body)

    elseBlock <- Mega.optional $ do
        open (keyword Keywords.else_)
        block nest Nothing

    close
    let conditionals = initialConditional :| additonalConditionals
    return (IfElse conditionals elseBlock)


{- Functions -}
----------------------------------------------------------------
func :: Parser MewlixFunction
func = do
    (name, params) <- open $ do
        keyword Keywords.function
        name   <- parseKey
        params <- parseParams
        return (name, params)
    body   <- block Nested Nothing
    close
    return (MewlixFunction name params body)

funcDef :: Nesting -> Parser Statement
funcDef _ = FunctionDef <$> func


{- Classes -}
----------------------------------------------------------------
type Constructor = MewlixFunction
type Methods     = [MewlixFunction]

classDef :: Nesting -> Parser Statement
classDef _ = do
    (name, parent) <- open $ do
        keyword Keywords.clowder
        name    <- parseKey
        parent  <- Mega.optional (keyword Keywords.extends >> parseKey)
        return (name, parent)
    (constructor, methods) <- (Mega.many . multiline) func >>= sortConstructor
    close

    let patchedConstructor = fmap patchConstructor constructor
    let patchedMethods = maybe methods (: methods) patchedConstructor

    (return . ClassDef) MewlixClass
        { className         = name
        , classExtends      = parent
        , classMethods      = patchedMethods
        , classConstructor  = patchedConstructor }

sortConstructor :: Methods -> Parser (Maybe Constructor, Methods) 
sortConstructor methods = do
    let wake = Key (unwrapKeyword Keywords.constructor)
    let predicate = (== wake) . funcName
    case List.partition predicate methods of
        ([] , xs)   -> return (Nothing, xs)
        ([x], xs)   -> return (Just x, xs)
        _           -> fail "Clowder cannot have more than one constructor!"

patchConstructor :: Constructor -> Constructor
patchConstructor constructor = do
    let returnHome = Return (PrimitiveExpr MewlixHome)
    let patch = (<> Block [returnHome])
    constructor { funcBody = patch (funcBody constructor) }


{- Return -}
----------------------------------------------------------------
returnKey :: Nesting -> Parser Statement
returnKey _ = do
    keyword Keywords.ret
    Return <$> expression

{- Assert -}
----------------------------------------------------------------
assert :: Nesting -> Parser Statement
assert _ = do
    keyword Keywords.assert
    Assert <$> expression <*> Mega.getSourcePos

{- Continue -}
----------------------------------------------------------------
continueKey :: Nesting -> Parser Statement
continueKey nesting = do
    keyword Keywords.catnap
    when (nesting < NestedInLoop)
        (fail "Cannot use loop keyword outside loop!")
    return Continue


{- Break -}
----------------------------------------------------------------
breakKey :: Nesting -> Parser Statement
breakKey nesting = do
    keyword Keywords.break
    when (nesting < NestedInLoop)
        (fail "Cannot use loop keyword outside loop!")
    return Break

{- For Loop -}
----------------------------------------------------------------
forEach :: Nesting -> Parser Statement
forEach nesting = do
    (key, iter) <- open $ do
        keyword Keywords.forEach
        key  <- parseKey
        keyword Keywords.forEachOf
        iter <- expression
        return (key, iter)
    body <- block (max nesting NestedInLoop) Nothing
    close
    return (ForEachLoop iter key body)


{- Import -}
----------------------------------------------------------------
importKey :: Nesting -> Parser Statement
importKey _ = do
    keyword Keywords.takes
    path <- parseModuleKey
    name <- Mega.optional (keyword Keywords.alias >> parseKey)
    return $ ImportModule (ModuleData path name)

importList :: Nesting -> Parser Statement
importList _ = do
    keyword Keywords.from
    path <- parseModuleKey
    keyword Keywords.takes
    keys <- Mega.sepBy1 parseKey (symbol ',')
    return $ ImportList (ModuleData path Nothing) keys

{- Watch/Catch -}
----------------------------------------------------------------
tryCatch :: Nesting -> Parser Statement
tryCatch nesting = do
    let localNest = max nesting Nested

    open (keyword Keywords.try)
    try_    <- block localNest (Just $ keyword Keywords.catch)

    key_    <- open $ do
        keyword Keywords.catch
        Mega.optional parseKey
    catch_  <- block localNest Nothing

    close
    return (TryCatch try_ key_ catch_)
