{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Rollbar.YesodSpec
  ( spec
  ) where

import qualified Network.Wai as W

import Data.IORef
import Data.Maybe
import Rollbar.Client
import Rollbar.Yesod
import Test.Hspec
import Yesod.Core
import Yesod.Test

data App = App
  { appRollbarSettings :: Settings
  , appRequestRef :: IORef (Maybe W.Request)
  }

mkYesod "App" [parseRoutes|
  /error ErrorR GET
  /success SuccessR GET
|]

instance HasSettings Handler where
  getSettings = getsYesod appRollbarSettings

instance Yesod App where
  yesodMiddleware handler = do
    requestRef <- getsYesod appRequestRef
    rollbarYesodMiddlewareWith (writeRequest requestRef) $
      defaultYesodMiddleware handler
    where
      writeRequest requestRef _ request _ =
        writeIORef requestRef $ Just request

getErrorR :: Handler ()
getErrorR = error "Boom"

getSuccessR :: Handler ()
getSuccessR = return ()

spec :: Spec
spec =
  describe "rollbarYesodMiddlewareWith" $ do
    context "when there is an error" $
      withApp $ yit "triggers a call to Rollbar" $ do
        get ErrorR
        statusIs 500
        requestRef <- appRequestRef <$> getTestYesod
        liftIO $ do
          request <- readIORef requestRef
          request `shouldSatisfy` isJust

    context "when there is no error" $
      withApp $ yit "does not trigger a call to Rollbar" $ do
        get SuccessR
        statusIs 200
        requestRef <- appRequestRef <$> getTestYesod
        liftIO $ do
          request <- readIORef requestRef
          request `shouldSatisfy` isNothing


withApp :: YesodSpec App -> Spec
withApp yspec = do
  app <- runIO getApplication
  yesodSpec app yspec
  where
    getApplication =
      App <$> readSettings "rollbar.yaml"
          <*> newIORef Nothing
