{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module Network.HTTP.Semantics.Client (
    -- * HTTP\/2 client
    Client,
    SendRequest,

    -- * Request
    Request (..),

    -- * Creating request
    requestNoBody,
    requestFile,
    requestStreaming,
    requestStreamingUnmask,
    requestBuilder,

    -- ** Trailers maker
    TrailersMaker,
    NextTrailersMaker (..),
    defaultTrailersMaker,
    setRequestTrailersMaker,

    -- * Response
    Response (..),

    -- ** Accessing response
    responseStatus,
    responseHeaders,
    responseBodySize,
    getResponseBodyChunk,
    getResponseTrailers,

    -- * Aux
    Aux (..),

    -- * Types
    Method,
    Path,
    FileSpec (..),
    FileOffset,
    ByteCount,
    module Network.HTTP.Semantics.ReadN,
    module Network.HTTP.Semantics.File,
) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import Data.IORef (readIORef)
import Network.HTTP.Types (Method, RequestHeaders, Status)

import Network.HTTP.Semantics
import Network.HTTP.Semantics.File
import Network.HTTP.Semantics.ReadN
import Network.HTTP.Semantics.Status

----------------------------------------------------------------

-- | Send a request and receive its response.
type SendRequest = forall r. Request -> (Response -> IO r) -> IO r

-- | Client type.
type Client a = SendRequest -> Aux -> IO a

-- | Request from client.
newtype Request = Request OutObj deriving (Show)

-- | Response from server.
newtype Response = Response InpObj deriving (Show)

-- | Additional information.
data Aux = Aux
    { auxPossibleClientStreams :: IO Int
    -- ^ How many streams can be created without blocking.
    }

----------------------------------------------------------------

-- | Creating request without body.
requestNoBody :: Method -> Path -> RequestHeaders -> Request
requestNoBody m p hdr = Request $ OutObj hdr' OutBodyNone defaultTrailersMaker
  where
    hdr' = addHeaders m p hdr

-- | Creating request with file.
requestFile :: Method -> Path -> RequestHeaders -> FileSpec -> Request
requestFile m p hdr fileSpec = Request $ OutObj hdr' (OutBodyFile fileSpec) defaultTrailersMaker
  where
    hdr' = addHeaders m p hdr

-- | Creating request with builder.
requestBuilder :: Method -> Path -> RequestHeaders -> Builder -> Request
requestBuilder m p hdr builder = Request $ OutObj hdr' (OutBodyBuilder builder) defaultTrailersMaker
  where
    hdr' = addHeaders m p hdr

-- | Creating request with streaming.
requestStreaming
    :: Method
    -> Path
    -> RequestHeaders
    -> ((Builder -> IO ()) -> IO () -> IO ())
    -> Request
requestStreaming m p hdr strmbdy = Request $ OutObj hdr' (OutBodyStreaming strmbdy) defaultTrailersMaker
  where
    hdr' = addHeaders m p hdr

-- | Like 'requestStreaming', but run the action with exceptions masked
requestStreamingUnmask
    :: Method
    -> Path
    -> RequestHeaders
    -> ((forall x. IO x -> IO x) -> (Builder -> IO ()) -> IO () -> IO ())
    -> Request
requestStreamingUnmask m p hdr strmbdy = Request $ OutObj hdr' (OutBodyStreamingUnmask strmbdy) defaultTrailersMaker
  where
    hdr' = addHeaders m p hdr

addHeaders :: Method -> Path -> RequestHeaders -> RequestHeaders
addHeaders m p hdr = (":method", m) : (":path", p) : hdr

-- | Setting 'TrailersMaker' to 'Response'.
setRequestTrailersMaker :: Request -> TrailersMaker -> Request
setRequestTrailersMaker (Request req) tm = Request req{outObjTrailers = tm}

----------------------------------------------------------------

-- | Getting the status of a response.
responseStatus :: Response -> Maybe Status
responseStatus (Response rsp) = getStatus $ inpObjHeaders rsp

-- | Getting the headers from a response.
responseHeaders :: Response -> HeaderTable
responseHeaders (Response rsp) = inpObjHeaders rsp

-- | Getting the body size from a response.
responseBodySize :: Response -> Maybe Int
responseBodySize (Response rsp) = inpObjBodySize rsp

-- | Reading a chunk of the response body.
--   An empty 'ByteString' returned when finished.
getResponseBodyChunk :: Response -> IO ByteString
getResponseBodyChunk (Response rsp) = inpObjBody rsp

-- | Reading response trailers.
--   This function must be called after 'getResponseBodyChunk'
--   returns an empty.
getResponseTrailers :: Response -> IO (Maybe HeaderTable)
getResponseTrailers (Response rsp) = readIORef (inpObjTrailers rsp)
