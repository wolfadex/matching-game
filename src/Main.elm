module Main exposing (..)

import Angle exposing (Angle)
import Animation exposing (Animation)
import Array exposing (Array)
import Array.Extra
import Axis3d
import Block3d
import Browser
import Browser.Events
import Camera3d
import Color exposing (Color)
import Direction3d
import Frame3d exposing (Frame3d)
import Json.Decode
import Length
import Pixels
import Point3d
import Quantity
import Random
import Random.List
import Scene3d
import Scene3d.Material
import Util.Maybe
import Vector3d
import Viewpoint3d


main : Program Int Model Msg
main =
    Browser.document
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


type alias Model =
    { seed : Random.Seed
    , board : Board
    , cursor : Cursor
    , rotation : ( Angle, Animation Angle )
    }


type alias Cursor =
    { left : Point2d
    , right : Point2d
    }


cellSize =
    1


boardWidth =
    -- columns, aka sides of the "circle"
    20


boardHeight =
    -- rows
    15


rotationDeg =
    360 / boardWidth


theta =
    rotationDeg / 2


rotationTime =
    -- ms
    50


type World
    = World Never


type Local
    = Local Never


type alias Board =
    Array Cell


type alias Cell =
    { symbol : Symbol
    , animation : Animation (Frame3d Length.Meters World Local)
    }


type Symbol
    = A
    | B
    | C
    | D


interpolateFrame3d : Frame3d Length.Meters World Local -> Frame3d Length.Meters World Local -> Float -> Frame3d Length.Meters World Local
interpolateFrame3d aFrame bFrame t =
    Frame3d.unsafe
        { originPoint =
            Point3d.interpolateFrom
                (Frame3d.originPoint aFrame)
                (Frame3d.originPoint bFrame)
                t
        , xDirection =
            Vector3d.interpolateFrom
                (Frame3d.xDirection aFrame
                    |> Direction3d.toVector
                )
                (Frame3d.xDirection bFrame
                    |> Direction3d.toVector
                )
                t
                |> Vector3d.direction
                |> Maybe.withDefault (Frame3d.xDirection aFrame)
        , yDirection =
            Vector3d.interpolateFrom
                (Frame3d.yDirection aFrame
                    |> Direction3d.toVector
                )
                (Frame3d.yDirection bFrame
                    |> Direction3d.toVector
                )
                t
                |> Vector3d.direction
                |> Maybe.withDefault (Frame3d.yDirection aFrame)
        , zDirection =
            Vector3d.interpolateFrom
                (Frame3d.zDirection aFrame
                    |> Direction3d.toVector
                )
                (Frame3d.zDirection bFrame
                    |> Direction3d.toVector
                )
                t
                |> Vector3d.direction
                |> Maybe.withDefault (Frame3d.zDirection aFrame)
        }


radius =
    cellSize
        / 2
        * sin (degrees (90 - theta))
        / sin (degrees theta)


init : Int -> ( Model, Cmd Msg )
init seedStarter =
    let
        ( initialBoard, seed ) =
            Random.step
                (Random.list (boardWidth * boardHeight)
                    (Random.List.choose [ A, B, C, D ]
                        |> Random.map Tuple.first
                    )
                    |> Random.map
                        (List.filterMap
                            (Maybe.map
                                (\symbol ->
                                    { symbol = symbol
                                    , animation = Animation.animation []
                                    }
                                )
                            )
                            >> Array.fromList
                        )
                )
                (Random.initialSeed seedStarter)

        cursor =
            { left = ( 0, 0 )
            , right = ( 1, 0 )
            }
    in
    ( { seed = seed
      , board = changeFocus { old = cursor, new = cursor } initialBoard
      , cursor = cursor
      , rotation = ( Angle.degrees (rotationDeg / 2), Animation.animation [] )
      }
    , Cmd.none
    )


type Msg
    = UserInput Input
    | Tick Float


type Input
    = RotateRight
    | RotateLeft
    | MoveUp
    | MoveDown
    | Swap


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onKeyDown keyDownDecoder
        , Browser.Events.onAnimationFrameDelta Tick
        ]


keyDownDecoder : Json.Decode.Decoder Msg
keyDownDecoder =
    Json.Decode.field "key" Json.Decode.string
        |> Json.Decode.andThen
            (\key ->
                case key of
                    "w" ->
                        Json.Decode.succeed (UserInput MoveUp)

                    "s" ->
                        Json.Decode.succeed (UserInput MoveDown)

                    "a" ->
                        Json.Decode.succeed (UserInput RotateLeft)

                    "d" ->
                        Json.Decode.succeed (UserInput RotateRight)

                    " " ->
                        Json.Decode.succeed (UserInput Swap)

                    _ ->
                        Json.Decode.fail "Not recognized input"
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick deltaMs ->
            ( { model
                | board =
                    Array.map
                        (\cell ->
                            { cell
                                | animation =
                                    Animation.animate
                                        Frame3d.atOrigin
                                        interpolateFrame3d
                                        deltaMs
                                        cell.animation
                                        |> Tuple.second
                            }
                        )
                        model.board
                , rotation =
                    let
                        ( defaultRot, anim ) =
                            model.rotation
                    in
                    ( defaultRot
                    , Animation.animate
                        defaultRot
                        Quantity.interpolateFrom
                        deltaMs
                        anim
                        |> Tuple.second
                    )
              }
            , Cmd.none
            )

        UserInput input ->
            case input of
                MoveUp ->
                    let
                        cursor =
                            { left =
                                model.cursor.left
                                    |> moveBy ( 0, 1 )
                                    |> constrainCursor
                            , right =
                                model.cursor.right
                                    |> moveBy ( 0, 1 )
                                    |> constrainCursor
                            }
                    in
                    ( { model
                        | cursor = cursor
                        , board = changeFocus { old = model.cursor, new = cursor } model.board
                      }
                    , Cmd.none
                    )

                MoveDown ->
                    let
                        cursor =
                            { left =
                                model.cursor.left
                                    |> moveBy ( 0, -1 )
                                    |> constrainCursor
                            , right =
                                model.cursor.right
                                    |> moveBy ( 0, -1 )
                                    |> constrainCursor
                            }
                    in
                    ( { model
                        | cursor = cursor
                        , board = changeFocus { old = model.cursor, new = cursor } model.board
                      }
                    , Cmd.none
                    )

                RotateLeft ->
                    let
                        cursor =
                            { left =
                                model.cursor.left
                                    |> moveBy ( -1, 0 )
                                    |> constrainCursor
                            , right =
                                model.cursor.right
                                    |> moveBy ( -1, 0 )
                                    |> constrainCursor
                            }
                    in
                    ( { model
                        | cursor = cursor
                        , board = changeFocus { old = model.cursor, new = cursor } model.board
                        , rotation =
                            let
                                ( rot, anim ) =
                                    model.rotation

                                ( frame, _ ) =
                                    Animation.animate rot
                                        Quantity.interpolateFrom
                                        0
                                        anim

                                nextRot =
                                    rot
                                        |> Quantity.minus (Angle.degrees rotationDeg)
                            in
                            ( nextRot
                            , Animation.animation
                                [ { frame = frame, offset = 0 }
                                , { frame = nextRot, offset = 100 }
                                ]
                            )
                      }
                    , Cmd.none
                    )

                RotateRight ->
                    let
                        cursor =
                            { left =
                                model.cursor.left
                                    |> moveBy ( 1, 0 )
                                    |> constrainCursor
                            , right =
                                model.cursor.right
                                    |> moveBy ( 1, 0 )
                                    |> constrainCursor
                            }
                    in
                    ( { model
                        | cursor = cursor
                        , board = changeFocus { old = model.cursor, new = cursor } model.board
                        , rotation =
                            let
                                ( rot, anim ) =
                                    model.rotation

                                ( frame, _ ) =
                                    Animation.animate rot
                                        Quantity.interpolateFrom
                                        0
                                        anim

                                nextRot =
                                    rot
                                        |> Quantity.plus (Angle.degrees rotationDeg)
                            in
                            ( nextRot
                            , Animation.animation
                                [ { frame = frame, offset = 0 }
                                , { frame = nextRot, offset = 100 }
                                ]
                            )
                      }
                    , Cmd.none
                    )

                Swap ->
                    let
                        leftIdx =
                            pointToIndex model.cursor.left

                        rightIdx =
                            pointToIndex model.cursor.right

                        leftCell =
                            Array.get leftIdx model.board

                        rightCell =
                            Array.get rightIdx model.board
                    in
                    ( { model
                        | board =
                            model.board
                                |> Util.Maybe.apply (Array.set leftIdx) rightCell
                                |> Util.Maybe.apply (Array.set rightIdx) leftCell
                      }
                    , Cmd.none
                    )


changeFocus : { old : Cursor, new : Cursor } -> Board -> Board
changeFocus cursors board =
    let
        oldLeftIdx =
            pointToIndex cursors.old.left

        oldRightIdx =
            pointToIndex cursors.old.right

        newLeftIdx =
            pointToIndex cursors.new.left

        newRightIdx =
            pointToIndex cursors.new.right
    in
    board
        |> Array.Extra.update oldLeftIdx
            (\cell -> { cell | animation = unfocusAnimation })
        |> Array.Extra.update oldRightIdx
            (\cell -> { cell | animation = unfocusAnimation })
        |> Array.Extra.update newLeftIdx
            (\cell -> { cell | animation = focusAnimation })
        |> Array.Extra.update newRightIdx
            (\cell -> { cell | animation = focusAnimation })


focusAnimation : Animation (Frame3d Length.Meters World Local)
focusAnimation =
    Animation.animation
        [ { frame = Frame3d.atOrigin
          , offset = 0
          }
        , { frame =
                Frame3d.atPoint
                    (Point3d.meters 0 (cellSize * 0.4) 0)
          , offset = 250
          }
        ]


unfocusAnimation : Animation (Frame3d Length.Meters World Local)
unfocusAnimation =
    Animation.animation
        [ { frame =
                Frame3d.atPoint
                    (Point3d.meters 0 (cellSize * 0.4) 0)
          , offset = 0
          }
        , { frame = Frame3d.atOrigin
          , offset = 250
          }
        ]


type alias Point2d =
    ( Int, Int )


moveBy : Point2d -> Point2d -> Point2d
moveBy ( x1, y1 ) ( x2, y2 ) =
    ( x1 + x2, y1 + y2 )


constrainCursor : Point2d -> Point2d
constrainCursor ( x, y ) =
    ( if x < 0 then
        x + boardWidth

      else if x >= boardWidth then
        x - boardWidth

      else
        x
    , if y < 0 then
        0

      else if y >= boardHeight then
        boardHeight - 1

      else
        y
    )


pointToIndex : Point2d -> Int
pointToIndex ( x, y ) =
    (y * boardWidth) + x


indexToPoint : Int -> Point2d
indexToPoint index =
    ( index |> modBy boardWidth
    , index // boardWidth
    )


view : Model -> Browser.Document Msg
view model =
    { title = "Matching Game"
    , body =
        [ let
            -- Create a single rectangle from its color and four vertices
            -- (Scene3d.quad can be used to create any flat four-sided shape)
            square =
                Scene3d.quad (Scene3d.Material.color Color.blue)
                    (Point3d.meters -1 -1 0)
                    (Point3d.meters 1 -1 0)
                    (Point3d.meters 1 1 0)
                    (Point3d.meters -1 1 0)

            -- Define our camera
            camera =
                Camera3d.perspective
                    { viewpoint =
                        Viewpoint3d.orbitZ
                            { focalPoint = Point3d.meters 0 0 6
                            , azimuth = Angle.degrees 90
                            , elevation = Angle.degrees 5
                            , distance = Length.meters 30
                            }
                    , verticalFieldOfView = Angle.degrees 30
                    }

            ( defaultRot, rotationAnim ) =
                model.rotation

            ( rotation, _ ) =
                Animation.animate
                    defaultRot
                    Quantity.interpolateFrom
                    0
                    rotationAnim
          in
          -- Render a scene that doesn't involve any lighting (no lighting is needed
          -- here since we provided a material that will result in a constant color
          -- no matter what lighting is used)
          Scene3d.sunny
            { -- Our scene has a single 'entity' in it
              entities =
                model.board
                    |> Array.toList
                    |> List.indexedMap (viewCell rotation model.cursor)
                    |> List.concat
            , sunlightDirection =
                Direction3d.xyZ
                    (Angle.degrees -90)
                    (Angle.degrees 45)
            , shadows = True
            , upDirection = Direction3d.positiveZ
            , camera = camera
            , clipDepth = Length.millimeters 1
            , background = Scene3d.transparentBackground
            , dimensions = ( Pixels.int 800, Pixels.int 600 )
            }
        ]
    }


viewCell : Angle -> Cursor -> Int -> Cell -> List (Scene3d.Entity World)
viewCell rotation cursor index cell =
    let
        ( x, y ) =
            indexToPoint index

        leftIdx =
            pointToIndex cursor.left

        rightIdx =
            pointToIndex cursor.right

        isFocused =
            index == leftIdx || index == rightIdx

        ( frame, _ ) =
            Animation.animate
                Frame3d.atOrigin
                interpolateFrame3d
                0
                cell.animation
    in
    List.filterMap identity
        [ Just
            (Scene3d.block
                (Scene3d.Material.matte (symbolToColor cell.symbol))
                (Block3d.centeredOn frame
                    ( Length.meters cellSize
                    , Length.meters cellSize
                    , Length.meters cellSize
                    )
                    |> Block3d.translateBy
                        (Vector3d.meters 0 radius (toFloat y))
                    |> Block3d.rotateAround
                        Axis3d.z
                        (Angle.degrees (rotationDeg * toFloat x)
                            |> Quantity.minus rotation
                        )
                )
            )
        , if isFocused then
            let
                size =
                    cellSize * 1.3
            in
            Just
                (Scene3d.block
                    (Scene3d.Material.matte Color.white)
                    (Block3d.with
                        { x1 = Length.meters (size / -2)
                        , x2 = Length.meters (size / 2)
                        , y1 = Length.meters (size / -2 - 0.1)
                        , y2 = Length.meters (size / 2 - 0.1)
                        , z1 = Length.meters (size / -2)
                        , z2 = Length.meters (size / 2)
                        }
                        |> Block3d.translateBy
                            (Vector3d.meters 0
                                radius
                                (toFloat y)
                            )
                        |> Block3d.rotateAround
                            Axis3d.z
                            (Angle.degrees (rotationDeg * toFloat x)
                                |> Quantity.minus rotation
                            )
                    )
                )

          else
            Nothing
        ]


symbolToColor : Symbol -> Color
symbolToColor symbol =
    case symbol of
        A ->
            Color.rgba 1 0 0 1

        B ->
            Color.rgba 0 1 0 1

        C ->
            Color.rgba 0 0 1 1

        D ->
            Color.rgba 0.5 0 0.5 1