module Util.Bool exposing (apply)


apply : (b -> b) -> Bool -> b -> b
apply fn cond b =
    if cond then
        fn b

    else
        b
