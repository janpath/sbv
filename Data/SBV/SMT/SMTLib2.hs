-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.SMT.SMTLib2
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Conversion of symbolic programs to SMTLib format, Using v2 of the standard
-----------------------------------------------------------------------------
{-# LANGUAGE PatternGuards #-}

module Data.SBV.SMT.SMTLib2(cvt, addNonEqConstraints) where

import Data.List (intercalate)

import Data.SBV.BitVectors.Data

addNonEqConstraints :: [[(String, CW)]] -> SMTLibPgm -> String
addNonEqConstraints nonEqConstraints (SMTLibPgm _ (aliasTable, pre, post)) = intercalate "\n" $
     pre
  ++ [ "; --- refuted-models ---" ]
  ++ concatMap nonEqs (map (map intName) nonEqConstraints)
  ++ post
 where intName (s, c)
          | Just sw <- s `lookup` aliasTable = (show sw, c)
          | True                             = (s, c)

nonEqs :: [(String, CW)] -> [String]
nonEqs []     =  []
nonEqs [sc]   =  ["(assert " ++ nonEq sc ++ ")"]
nonEqs (sc:r) =  ["(assert (or " ++ nonEq sc]
              ++ map (("           " ++) . nonEq) r
              ++ ["        ))"]

nonEq :: (String, CW) -> String
nonEq (s, c) = "(not (= " ++ s ++ " " ++ cvtCW c ++ "))"

-- TODO: fix this
cvtCW :: CW -> String
cvtCW = show

cvt :: Bool                                        -- ^ is this a sat problem?
    -> [String]                                    -- ^ extra comments to place on top
    -> [(Quantifier, NamedSymVar)]                 -- ^ inputs and aliasing names
    -> [(SW, CW)]                                  -- ^ constants
    -> [((Int, (Bool, Int), (Bool, Int)), [SW])]   -- ^ auto-generated tables
    -> [(Int, ArrayInfo)]                          -- ^ user specified arrays
    -> [(String, SBVType)]                         -- ^ uninterpreted functions/constants
    -> [(String, [String])]                        -- ^ user given axioms
    -> Pgm                                         -- ^ assignments
    -> SW                                          -- ^ output variable
    -> ([String], [String])
cvt isSat comments qinps consts tbls arrs uis axs asgnsSeq out = (pre, extractModel)
  where pre  =  [ "; Automatically generated by SBV. Do not edit." ]
             ++ map ("; " ++) comments
             ++ [ "(set-option :produce-models true)"
                , "; --- skolem constants ---"
                ]
             ++ ["(declare-fun " ++ show s ++ " " ++ smtFunType ss s ++ ")" | Right (s, ss) <- skolemMap]
             ++ [ "; --- formula ---" ]
             ++ [ "(assert (forall (" ++ intercalate " " ["(" ++ show s ++ " " ++ smtType s ++ ")" | Left s <- skolemMap] ++ ")" ]
             -- BOGUS
             ++ [ "(bvuge s0 (s1 s0))" ]
             ++ ["))"]
        extractModel = "(check-sat)" : [extract s ss | Right (s, ss) <- skolemMap]
          where extract s [] = "(get-value (" ++ show s ++ "))"
                extract s ss = "(eval (" ++ show s ++ concat [" #x0000" | _ <- ss] ++ "))"
        skolemMap = skolemize (if isSat then qinps else map flipQ qinps)
          where flipQ (ALL, x) = (EX, x)
                flipQ (EX, x)  = (ALL, x)

-- If Left, it's universal. If Right, it's existential with the dependent universals listed
type Skolemized = Either SW (SW, [SW])

-- Skolemize the quantifier section
skolemize :: [(Quantifier, NamedSymVar)] -> [Skolemized]
skolemize qinps = go qinps ([], [])
  where go []                   (_,  sofar) = reverse sofar
        go ((ALL, (v, _)):rest) (us, sofar) = go rest (v:us, Left v : sofar)
        go ((EX,  (v, _)):rest) (us, sofar) = go rest (us,   Right (v, reverse us) : sofar)

{-
cvt _isSat comments qinps _consts _tbls _arrs _uis _axs _asgnsSeq _out
  | not (needsExistentials (map fst qinps))
  = error "SBV: No existential variables present. Use prove/sat instead."
  | True
  = (pre, post ++ extractModel)
  where pre  = [ "; Automatically generated by SBV. Do not edit."
               , "(set-option :produce-models true)"
               ]
               ++ map ("; " ++) comments
               ++ topDecls
        post = [ "(assert (forall ((s2 (_ BitVec 16))) (and (bvuge s1 #x0005) (bvuge (bvsub (bvadd s2 s1) #x0001) s0))))"
               ]
        topExists = takeWhile (\(q, _) -> q == EX) qinps
        topDecls  = ["(declare-fun " ++ show s ++ " () " ++ smtType s ++ ")" | (_, (s, _)) <- topExists]
        modelVals = [show s | (_, (s, _)) <- topExists]
        extractModel = "(check-sat)" : ["(get-value (" ++ v ++ "))" | v <- modelVals]
-}

smtType :: SW -> String
smtType s = "(_ BitVec " ++ show (sizeOf s) ++ ")"

smtFunType :: [SW] -> SW -> String
smtFunType ss s = "(" ++ intercalate " " (map smtType ss) ++ ") " ++ smtType s
