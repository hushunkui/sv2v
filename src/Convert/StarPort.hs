{- sv2v
 - Author: Zachary Snow <zach@zachjs.com>
 -
 - Conversion for `.*` in module instantiation
 -}

module Convert.StarPort (convert) where

import Control.Monad.Writer
import qualified Data.Map.Strict as Map

import Convert.Traverse
import Language.SystemVerilog.AST

convert :: AST -> AST
convert descriptions =
    traverseDescriptions (traverseModuleItems mapInstance) descriptions
    where
        modulePorts = execWriter $ collectDescriptionsM getPorts descriptions
        getPorts :: Description -> Writer (Map.Map Identifier [Identifier]) ()
        getPorts (Part _ name ports _) = tell $ Map.singleton name ports
        getPorts _ = return ()

        mapInstance :: ModuleItem -> ModuleItem
        mapInstance (Instance m p x bindings) =
            Instance m p x $ concatMap expandBinding bindings
            where
                alreadyBound :: [Identifier]
                alreadyBound = map fst bindings
                expandBinding :: PortBinding -> [PortBinding]
                expandBinding ("*", Nothing) =
                    case Map.lookup m modulePorts of
                        Just l ->
                            map (\port -> (port, Just $ Ident port)) $
                            filter (\s -> not $ elem s alreadyBound) $ l
                        -- if we can't find it, just skip :(
                        Nothing -> [("*", Nothing)]
                expandBinding other = [other]
        mapInstance other = other
