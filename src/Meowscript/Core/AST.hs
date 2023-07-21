{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TemplateHaskell #-}

module Meowscript.Core.AST
( Prim(..)
, Expr(..)
, Unop(..)
, Binop(..)
, MeowIf(..)
, KeyType(..)
, MeowCatch(..)
, Statement(..)
, ReturnValue(..)
, MeowException(..)
, PrimRef
, ObjectMap
, Key
, Overwrite
, Params
, Environment
, Closure
, CatException
, Evaluator
, InnerFunc
, Condition
, Block
, Qualified
, IsLoop
, meowBool
, shouldBreak
, returnAsPrim
, MeowState(..)
, MeowCache
, meowArgs
, meowLib
, meowStd
, meowCache
, meowPath
, meowSocket
, meowInclude
, meowFlags
, meowDefines
) where

import Meowscript.Utils.Types
import qualified Data.Set as Set
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Control.Monad.Reader (ReaderT)
import Control.Monad.Except (ExceptT)
import Data.IORef (IORef)
import Network.Socket (Socket)
import Lens.Micro.Platform (makeLenses)

{- Evaluator -}
--------------------------------------------
type Key = Text.Text
type Params = [Key]
type Overwrite = Bool
type InnerFunc = Evaluator Prim

type PrimRef = IORef Prim
type ObjectMap = Map.Map Key PrimRef

type Environment = IORef ObjectMap
type Closure = Environment
type CatException = (MeowException, Text.Text)

type Evaluator a = ReaderT (MeowState, Environment) (ExceptT CatException IO) a


{- AST - Primitives -}
--------------------------------------------
data Prim =
      MeowString Text.Text
    | MeowKey KeyType
    | MeowBool Bool
    | MeowInt Int
    | MeowDouble Double
    | MeowLonely
    | MeowList [Prim]
    | MeowFunc Params [Statement] Closure
    | MeowObject ObjectMap
    | MeowIFunc Params InnerFunc

data KeyType =
      KeyModify Key
    | KeyNew Key
    | KeyRef (PrimRef, Prim)

{- This is extremely different from actually pretty-printing Meowscript values!!!
 - Since Meowscript handles IORefs as primitives, a pretty-printing function
 - has to be wrapped in an IO monad to be used, and this 'show' instance is far from enough.
 - Thus, I'm using this to facilitate my debugging instead. -}
instance Show Prim where
    show (MeowString x) = show x
    show (MeowKey x) = concat ["<key: \"", show x, "\">" ]
    show (MeowInt x) = show x
    show (MeowBool x) = show x
    show (MeowDouble x) = show x
    show MeowLonely = "<lonely>"
    show (MeowList xs) = show $ map show xs
    show (MeowFunc {}) = "<func>"
    show (MeowObject _) = "<object>"
    show (MeowIFunc _ _) = "<inner-func>"

instance Show KeyType where
    show (KeyModify x) = Text.unpack x
    show (KeyNew x) = Text.unpack x
    show (KeyRef _) = "<ref>"

meowBool :: Prim ->  Bool
meowBool (MeowBool a) = a
meowBool (MeowList a) = (not . null) a
meowBool (MeowString a) = (not . Text.null) a
meowBool (MeowObject a) = (not . Map.null) a
meowBool MeowLonely = False
meowBool _ = True



{- AST - Expressions -}
--------------------------------------------

data Expr =
      ExpPrim Prim
    | ExpUnop Unop Expr 
    | ExpBinop Binop Expr Expr
    | ExpList [Expr]
    | ExpObject [(Key, Expr)]
    | ExpLambda [Key] Expr
    | ExpMeowAnd Expr Expr
    | ExpMeowOr Expr Expr
    | ExpYarn Expr
    | ExpTernary Expr Expr Expr
    | ExpDotOp Expr Expr
    | ExpBoxOp Expr Expr
    | ExpCall Expr [Expr] 
    deriving (Show)

data Unop =
      MeowLen 
    | MeowPeek
    | MeowKnockOver
    | MeowNot 
    | MeowNegate
    | MeowPaw
    | MeowClaw
    deriving (Show)

data Binop =
      MeowAdd
    | MeowSub 
    | MeowMul 
    | MeowDiv 
    | MeowMod
    | MeowCompare [Ordering]
    | MeowAssign
    | MeowConcat 
    | MeowPush
    | MeowPow
    deriving (Show)


{- AST - Statements -}
--------------------------------------------
type Condition = Expr
type Block = [Statement]
type Qualified = Maybe Text.Text
type IsLoop = Bool

data MeowIf = MeowIf Condition Block deriving(Show)
data MeowCatch = MeowCatch (Maybe Expr) Block deriving (Show)

data Statement =
      StmExpr Expr
    | StmWhile Condition Block
    | StmFor (Expr, Expr, Expr) Block
    | StmIf [MeowIf]
    | StmIfElse [MeowIf] Block
    | StmFuncDef Expr Params [Statement]
    | StmReturn Expr
    | StmImport FilePathT (Maybe Key)
    | StmTryCatch Block [MeowCatch]
    | StmContinue
    | StmBreak
    deriving (Show)

data ReturnValue =
      RetVoid
    | RetBreak
    | RetContinue
    | RetValue Prim
    deriving (Show)

instance Eq ReturnValue where
    RetVoid == RetVoid = True
    RetBreak == RetBreak = True
    RetContinue == RetContinue = True
    RetValue _ == RetValue _ = True
    _ == _ = False

shouldBreak :: ReturnValue -> Bool
shouldBreak RetBreak = True
shouldBreak (RetValue _) = True
shouldBreak _ = False

returnAsPrim :: ReturnValue -> Prim
returnAsPrim (RetValue x) = x
returnAsPrim _ = MeowLonely


{- Exceptions -}
--------------------------------------------
data MeowException =
      MeowBadVar
    | MeowInvalidOp
    | MeowBadSyntax
    | MeowBadBox
    | MeowDivByZero
    | MeowNotKey
    | MeowBadArgs
    | MeowBadToken
    | MeowBadFunc
    | MeowBadImport
    | MeowBadIFunc
    | MeowBadValue
    | MeowCatOnComputer
    | MeowNotKeyword
    | MeowBadFile
    | MeowBadFuncDef
    | MeowBadHash
    | MeowUnexpected
    deriving (Eq)

instance Show MeowException where
    show MeowBadVar = exc "InvalidVariable"
    show MeowBadSyntax = exc "Syntax"
    show MeowInvalidOp = exc "InvalidOperation"
    show MeowBadBox = exc "InvalidBox"
    show MeowDivByZero = exc "DivisionByZero"
    show MeowNotKey = exc "InvalidKey"
    show MeowBadArgs = exc "Argument"
    show MeowBadToken = exc "InvalidToken"
    show MeowBadFunc = exc "InvalidFunction"
    show MeowBadImport = exc "InvalidImport"
    show MeowBadIFunc = exc "InvalidInnerFunction"
    show MeowBadValue = exc "InvalidValue"
    show MeowCatOnComputer = exc "CatOnComputer"
    show MeowNotKeyword = exc "KeywordException"
    show MeowBadFile = exc "File"
    show MeowBadFuncDef = exc "FunctionDefinition"
    show MeowBadHash = exc "Hashing"
    show MeowUnexpected = exc "Unexpected" 

exc :: String -> String
exc = (++ "Exception")


{- MeowState -}
--------------------------------------------------------
type MeowCache = IORef (Map.Map FilePathT Environment)

data MeowState = MeowState
    { _meowArgs     :: [Text.Text]                  -- Command-line arguments.
    , _meowLib      :: IO ObjectMap
    , _meowStd      :: Set.Set FilePathT            -- Standard files.
    , _meowCache    :: Maybe MeowCache              -- File import cache.
    , _meowPath     :: FilePathT                    -- The path to the current file.
    , _meowSocket   :: Maybe Socket
    , _meowInclude  :: [FilePathT]                  -- 'Include' paths.
    , _meowFlags    :: Set.Set Text.Text
    , _meowDefines  :: Map.Map Text.Text Text.Text  -- Meta constant definitions.
    }

$(makeLenses ''MeowState)

{- To add:
 - Socket address.
 - Compile flags (?).
 - 'Define'-style flags. (?) -}
