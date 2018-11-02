{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ViewPatterns #-}

module Unison.Result where

import           Control.Monad.Except           ( ExceptT(..) )
import           Data.Functor.Identity
import qualified Control.Monad.Fail            as Fail
import           Control.Monad.Trans.Maybe      ( MaybeT(..) )
import           Control.Monad.Writer           ( WriterT(..)
                                                , runWriterT
                                                , MonadWriter(..)
                                                )
import           Data.Maybe
import           Data.Sequence                  ( Seq )
import           Unison.Names                   ( Name )
import qualified Unison.Parser                 as Parser
import           Unison.Paths                   ( Path )
import           Unison.Term                    ( AnnotatedTerm )
import qualified Unison.Typechecker.Context    as Context
import           Control.Error.Util             ( note)

type Result notes = ResultT notes Identity

type ResultT notes f = MaybeT (WriterT notes f)

type Term v loc = AnnotatedTerm v loc

data Note v loc
  = Parsing (Parser.Err v)
  | InvalidPath Path (Term v loc) -- todo: move me!
  | UnknownSymbol v loc
  | TypeError (Context.ErrorNote v loc)
  | TypeInfo (Context.InfoNote v loc)
  | CompilerBug (CompilerBug v loc)
  deriving Show

data CompilerBug v loc
  = TopLevelComponentNotFound v (Term v loc)
  | ResolvedNameNotFound v loc Name
  deriving Show

result :: Result notes a -> Maybe a
result (Result _ may) = may

pattern Result notes may = MaybeT (WriterT (Identity (may, notes)))
{-# COMPLETE Result #-}

isSuccess :: Functor f => ResultT note f a -> f Bool
isSuccess = (isJust . fst <$>) . runResultT

isFailure :: Functor f => ResultT note f a -> f Bool
isFailure = (isNothing . fst <$>) . runResultT

toMaybe :: Functor f => ResultT note f a -> f (Maybe a)
toMaybe = (fst <$>) . runResultT

runResultT :: ResultT notes f a -> f (Maybe a, notes)
runResultT = runWriterT . runMaybeT

toEither :: Functor f => ResultT notes f a -> ExceptT notes f a
toEither r = ExceptT (fmap go $ runResultT r)
  where go (may, notes) = note notes may

tell1 :: Monad f => note -> ResultT (Seq note) f ()
tell1 = tell . pure

fromParsing'
  :: Monad f => Either (Parser.Err v) a -> ResultT (Seq (Note v loc)) f a
fromParsing' (Left e) = do
  tell1 $ Parsing e
  Fail.fail ""
fromParsing' (Right a) = pure a

fromParsing :: Either (Parser.Err v) a -> Result (Seq (Note v loc)) a
fromParsing = fromParsing'

tellAndFail :: Monad f => note -> ResultT (Seq note) f a
tellAndFail note = tell1 note *> Fail.fail "Elegantly and responsibly"
