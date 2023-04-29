{-# LANGUAGE OverloadedStrings #-} 

module Meowscript.Core.Blocks
( runEvaluator 
, evaluate
, runStatements
, runBlock
) where

import Meowscript.Core.AST
import Meowscript.Core.Evaluate
import Meowscript.Core.Operations
import Meowscript.Core.Environment
import Meowscript.Core.Messages
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.Map as Map
import qualified Data.List as List
import Control.Monad.State (get, liftIO, runStateT)
import Control.Monad.Except (throwError, runExceptT)
import Control.Monad (void, when)
import Data.Functor ((<&>))

{- Run all statements from root. -}
runEvaluator :: EnvStack -> Evaluator a -> IO (Either Text.Text (a, EnvStack))
runEvaluator env x = runExceptT (runStateT x env)

{- Evaluating Expressions -}

{- Basic Expressions -}
evaluate :: Expr -> Evaluator Prim
evaluate (EPrim x) = return x
evaluate (EBinop op expA expB) = do
    a <- evaluate expA
    b <- evaluate expB
    binop op a b
evaluate (EUnop op expA) = do
    a <- evaluate expA
    unop op a

{- Lists + Objects -}
evaluate (EList xs) = do
    prims <- mapM evaluate xs
    (return . MeowList) prims
evaluate (EObject xs) = do
    asPrims <- mapM (\(key, exp') -> evaluate exp' >>= ensureValue
                        >>= (\x -> return (key, x))) xs
    let mapObject = Map.fromList asPrims
    (return . MeowObject) mapObject

{- Dot Operator -}
evaluate x@(EDot {}) = do
    xs <- unwrapDot x
    (return . MeowTrail) xs
    
{- Methods -}
evaluate (ECall args x@(EDot {})) = do
    xs <- unwrapDot x
    fn <- lookUpTrail xs
    let home = init xs -- All but the function name.
    methodCall args home fn

{- Functions -}
evaluate (ECall args name) = do
    fnName <- evaluate name
    case fnName of
        (MeowKey x) -> funcCall x args
        _ -> throwError "Invalid function name!"

{- Inner Functions -}
evaluate ERead = liftIO TextIO.getLine <&> MeowString
evaluate (EWrite x) = do
    evaluate x >>= ensureValue >>= (liftIO . print)
    return MeowLonely

{- Ensures a value will be passed instead of an atom. -}
ensureValue :: Prim -> Evaluator Prim
ensureValue (MeowKey x) = lookUpVar x >>= ensureValue
ensureValue (MeowTrail xs) = lookUpTrail xs >>= ensureValue
ensureValue x = return x


{- Dot Operator -}
unwrapDot :: Expr -> Evaluator [Text.Text]
unwrapDot (EDot x y) = do
    x' <- unwrapDot x
    y' <- unwrapDot y
    return (x' ++ y')
unwrapDot (EPrim (MeowTrail xs)) = return xs
unwrapDot (EPrim (MeowKey x)) = return [x]
unwrapDot x = do
    x' <- evaluate x
    case x' of
        (MeowKey key) -> return [key]
        _ -> throwError (Text.concat ["Invalid token in trail: ", showT x'])


{- Function Call -}
funcCall :: Name -> [Expr] -> Evaluator Prim
funcCall name args = do
    x <- keyExists name
    if not x then
        throwError (Text.concat ["Function doesn't exist! : ", name])
    else do lookUpVar name >>= runFunc args
        
runFunc :: [Expr] -> Prim -> Evaluator Prim
runFunc args (MeowFunc params body) = do
    when (length params > length args)
        (throwError "Too few arguments for function!")
    let z = zip params args
    stackPush
    funcArgs z
    ret <- runStatements body
    stackPop
    return ret
runFunc _ _ = throwError "Invalid function call!"

{- Method Call -}
methodCall :: [Expr] -> [Key] -> Prim -> Evaluator Prim
methodCall args trail (MeowFunc params body) = do
    when (length params > length args)
        (throwError "Too few arguments for function!")
    let z = zip params args
    stackPush
    funcArgs z
    addToTop "home" (MeowTrail trail)
    ret <- runStatements body
    stackPop
    return ret
methodCall _ _ _ = throwError "Invalid method call!" 


{- Add function arguments to the environment. -}
funcArgs :: [(Key, Expr)] -> Evaluator ()
funcArgs [] = return ()
funcArgs ((key, expr):xs) = do
    evaluate expr >>= ensureValue >>= addToTop key
    funcArgs xs


{- Helper functions to distinguish between statements. -}
isFuncDef :: Statement -> Bool
isFuncDef (SFuncDef {}) = True
isFuncDef _ = False


{- Run block in proper order: Function definitions, then other statements. -}
runBlock :: [Statement] -> Evaluator Prim
runBlock xs = do
    let (funcDefs, rest) = List.partition isFuncDef xs
    void $ runStatements funcDefs
    runStatements rest


{- Running Statements -}
runStatements :: [Statement] -> Evaluator Prim
runStatements [] = return MeowVoid

runStatements ((SReturn x):_) = evaluate x >>= ensureValue

runStatements (SBreak:_) = return MeowBreak
runStatements (SContinue:_) = return MeowVoid

runStatements ((SExpr x):xs) =
    runExprS x >> runStatements xs

runStatements ((SFuncDef name args body):xs) =
    runFuncDef name args body >> runStatements xs

runStatements (x:xs) = do
    stackPush
    ret <- run
    stackPop
    if ret /= MeowVoid
        then return ret
        else runStatements xs
    where run = case x of
            (SOnlyIf cond body) -> runIf cond body
            (SIfElse cond ifB elseB) -> runIfElse cond ifB elseB
            (SWhile cond body) -> runWhile cond body
            _ -> return MeowVoid


{- Boolean Condition -}
asCondition :: Expr -> Evaluator Bool
asCondition x = asBool <$> (evaluate x >>= ensureValue)

{- Expression Statement -}
runExprS :: Expr -> Evaluator Prim
runExprS = evaluate 

{- If Block (Single) -}
runIf :: Expr -> [Statement] -> Evaluator Prim
runIf x body = do
    condition <- asCondition x 
    if condition
      then runBlock body
      else return MeowVoid

{- If Else -}
runIfElse :: Expr -> [Statement] -> [Statement] -> Evaluator Prim
runIfElse x ifB elseB = do
    condition <- asCondition x
    if condition
        then runBlock ifB
        else runBlock elseB

{- While Loop -}
{- Notes:
 - Any return value that isn't MeowVoid implies the end of the loop. -}
runWhile :: Expr -> [Statement] -> Evaluator Prim
runWhile x body = do
    ret <- runBlock body
    condition <- asCondition x
    let isBreak = ret /= MeowVoid 
    if condition && not isBreak
        then runWhile x body
        else return ret

{- Function Definition -}
runFuncDef :: Name -> Args -> [Statement] -> Evaluator Prim
runFuncDef name args body = do
    let func = MeowFunc args body
    insertVar name func
    return MeowVoid
