{- sv2v
 - Author: Zachary Snow <zach@zachjs.com>
 -
 - Elaboration of size casts, dimension query system functions, and ternary
 - expressions where the condition references a localparam.
 -
 - Our conversions generate a lot of ternary expressions. This conversion
 - attempts to make the code output a bit cleaner. Note that we can only do this
 - simplification on localparams because parameters can be overridden at
 - instantiation.
 -
 - This conversion applies the heuristic that it will only make substitutions
 - into a ternary condition if making substitutions immediately enables the
 - expression to be simplified further.
 -}

module Convert.Simplify (convert) where

import Control.Monad (when)

import Convert.ExprUtils
import Convert.Scoper
import Convert.Traverse
import Language.SystemVerilog.AST

convert :: [AST] -> [AST]
convert = map $ traverseDescriptions convertDescription

convertDescription :: Description -> Description
convertDescription =
    partScoper traverseDeclM traverseModuleItemM traverseGenItemM traverseStmtM

traverseDeclM :: Decl -> Scoper Expr Decl
traverseDeclM decl = do
    case decl of
        Param Localparam _ x e ->
            when (isSimpleExpr e) $ insertElem x e
        _ -> return ()
    let mi = MIPackageItem $ Decl decl
    mi' <- traverseModuleItemM mi
    let MIPackageItem (Decl decl') = mi'
    return decl'

isSimpleExpr :: Expr -> Bool
isSimpleExpr Ident{}   = True
isSimpleExpr Number{}  = True
isSimpleExpr String{}  = True
isSimpleExpr (Dot   e _  ) = isSimpleExpr e
isSimpleExpr (Bit   e _  ) = isSimpleExpr e
isSimpleExpr (Range e _ _) = isSimpleExpr e
isSimpleExpr _ = False

traverseModuleItemM :: ModuleItem -> Scoper Expr ModuleItem
traverseModuleItemM (Instance m p x rs l) = do
    p' <- mapM paramBindingMapper p
    traverseExprsM traverseExprM $ Instance m p' x rs l
    where
        paramBindingMapper (param, Left t) = do
            t' <- traverseNestedTypesM (traverseTypeExprsM substituteExprM) t
            return (param, Left t')
        paramBindingMapper (param, Right e) = return (param, Right e)
traverseModuleItemM item = traverseExprsM traverseExprM item

traverseGenItemM :: GenItem -> Scoper Expr GenItem
traverseGenItemM = traverseGenItemExprsM traverseExprM

traverseStmtM :: Stmt -> Scoper Expr Stmt
traverseStmtM stmt = traverseStmtExprsM traverseExprM stmt

traverseExprM :: Expr -> Scoper Expr Expr
traverseExprM = embedScopes convertExpr

substituteExprM :: Expr -> Scoper Expr Expr
substituteExprM = embedScopes substitute

convertExpr :: Scopes Expr -> Expr -> Expr
convertExpr info (Cast (Right c) e) =
    Cast (Right c') e'
    where
        c' = convertExpr info $ substitute info c
        e' = convertExpr info e
convertExpr info (DimFn f v e) =
    DimFn f v e'
    where e' = convertExpr info $ substitute info e
convertExpr info (Call (Ident "$clog2") (Args [e] [])) =
    if val' == val
        then val
        else val'
    where
        e' = convertExpr info $ substitute info e
        val = Call (Ident "$clog2") (Args [e'] [])
        val' = simplifyStep val
convertExpr info (Mux cc aa bb) =
    if before == after
        then simplifyStep $ Mux cc' aa' bb'
        else simplifyStep $ Mux after aa' bb'
    where
        before = substitute info cc'
        after = convertExpr info before
        aa' = convertExpr info aa
        bb' = convertExpr info bb
        cc' = convertExpr info cc
convertExpr info (BinOp op e1 e2) =
    simplifyStep $ BinOp op
        (convertExpr info e1)
        (convertExpr info e2)
convertExpr info (UniOp op expr) =
    simplifyStep $ UniOp op $ convertExpr info expr
convertExpr info (Repeat expr exprs) =
    simplifyStep $ Repeat
        (convertExpr info expr)
        (map (convertExpr info) exprs)
convertExpr info (Concat exprs) =
    simplifyStep $ Concat (map (convertExpr info) exprs)
convertExpr info expr =
    traverseSinglyNestedExprs (convertExpr info) expr

substitute :: Scopes Expr -> Expr -> Expr
substitute scopes expr =
    traverseNestedExprs substitute' expr
    where
        substitute' :: Expr -> Expr
        substitute' (Ident x) =
            case lookupElem scopes x of
                Nothing -> Ident x
                Just (_, _, e) -> e
        substitute' other = other
