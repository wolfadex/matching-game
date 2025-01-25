module Animation exposing (..)


type alias Animation a =
    { state : State a
    , frames : List (KeyFrame a)
    }


type State a
    = NoAnimation
    | Animating Float
    | Complete a


animation : List (KeyFrame a) -> Animation a
animation frames =
    { state =
        case frames of
            [] ->
                NoAnimation

            keyFrame :: [] ->
                Complete keyFrame.frame

            _ ->
                Animating 0
    , frames = frames
    }


type alias KeyFrame a =
    { frame : a
    , offset : Float
    }


animate : a -> (a -> a -> Float -> a) -> Float -> Animation a -> ( a, Animation a )
animate default interpolate deltaTime anim =
    case anim.state of
        NoAnimation ->
            ( default, anim )

        Complete frame ->
            ( frame, anim )

        Animating elapsedTime ->
            let
                ( frame, isComplete ) =
                    animateHelper default interpolate anim.frames (elapsedTime + deltaTime)
            in
            ( frame
            , { anim
                | state =
                    if isComplete then
                        Complete frame

                    else
                        Animating (elapsedTime + deltaTime)
              }
            )


animateHelper : a -> (a -> a -> Float -> a) -> List (KeyFrame a) -> Float -> ( a, Bool )
animateHelper default interpolate frames elapsedTime =
    case frames of
        [] ->
            ( default, True )

        next :: [] ->
            ( next.frame, True )

        a :: b :: rest ->
            if elapsedTime <= 0 then
                ( a.frame, False )

            else if elapsedTime == b.offset then
                ( b.frame, False )

            else if elapsedTime <= b.offset then
                let
                    t =
                        elapsedTime / b.offset
                in
                ( interpolate a.frame b.frame t
                , False
                )

            else
                animateHelper default interpolate (b :: rest) (elapsedTime - a.offset)
