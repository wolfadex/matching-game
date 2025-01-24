module Util.Maybe exposing (apply)


apply : (a -> b -> b) -> Maybe a -> b -> b
apply fn maybeA b =
    case maybeA of
        Nothing ->
            b

        Just a ->
            fn a b
