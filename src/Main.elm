port module Main exposing (..)

import Angle exposing (Angle)
import Animation exposing (Animation)
import Array exposing (Array)
import Array.Extra
import Axis3d exposing (Axis3d)
import Block3d
import Browser
import Browser.Dom
import Browser.Events
import Camera3d
import Color exposing (Color)
import Direction3d exposing (Direction3d)
import Frame3d exposing (Frame3d)
import Html
import Html.Attributes
import Json.Decode
import Length exposing (Length)
import Pixels
import Point3d
import Quantity
import Random
import Random.List
import Scene3d
import Scene3d.Material
import Set exposing (Set)
import Task
import Util.Bool
import Util.Maybe
import Vector3d exposing (Vector3d)
import Viewpoint3d


main : Program { seedStarter : Int, windowWidth : Int, windowHeight : Int } Model Msg
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
    , windowWidth : Int
    , windowHeight : Int
    , score : Int
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
    10


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
    | None


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


init : { seedStarter : Int, windowWidth : Int, windowHeight : Int } -> ( Model, Cmd Msg )
init { seedStarter, windowWidth, windowHeight } =
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
      , windowWidth = 0
      , windowHeight = 0
      , score = 0
      }
    , Browser.Dom.getViewport
        |> Task.perform (\{ viewport } -> WindowResized (round viewport.width) (round viewport.height))
    )


type Msg
    = UserInput Input
    | Tick Float
    | WindowResized Int Int


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onKeyDown keyDownDecoder
        , Browser.Events.onAnimationFrameDelta Tick
        , Browser.Events.onResize WindowResized
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


port playSound : String -> Cmd msg


type Input
    = RotateRight
    | RotateLeft
    | MoveUp
    | MoveDown
    | Swap


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        WindowResized width height ->
            ( { model | windowWidth = width, windowHeight = height }
            , Cmd.none
            )

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
                        |> dropCells
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
                    , playSound "ROTATE"
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
                    , playSound "ROTATE"
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
                    case ( leftCell, rightCell ) of
                        ( Just left, Just right ) ->
                            let
                                swappedBoard =
                                    model.board
                                        |> Array.set leftIdx
                                            { right
                                                | animation =
                                                    swapAnimation
                                                        (Frame3d.atOrigin
                                                            |> Frame3d.translateBy (Vector3d.meters 0 radius 0)
                                                            |> Frame3d.rotateAround Axis3d.z (Angle.degrees rotationDeg)
                                                            |> Frame3d.translateBy (Vector3d.meters 0 -radius 0)
                                                        )
                                                        (Frame3d.atOrigin
                                                            |> Frame3d.translateBy (Vector3d.meters 0 (cellSize * 0.4) 0)
                                                        )
                                            }
                                        |> Array.set rightIdx
                                            { left
                                                | animation =
                                                    swapAnimation
                                                        (Frame3d.atOrigin
                                                            |> Frame3d.translateBy (Vector3d.meters 0 radius 0)
                                                            |> Frame3d.rotateAround Axis3d.z (Angle.degrees -rotationDeg)
                                                            |> Frame3d.translateBy (Vector3d.meters 0 -radius 0)
                                                        )
                                                        (Frame3d.atOrigin
                                                            |> Frame3d.translateBy (Vector3d.meters 0 (cellSize * 0.4) 0)
                                                        )
                                            }
                            in
                            if left.symbol == right.symbol then
                                ( { model | board = swappedBoard }
                                , Cmd.none
                                )

                            else
                                let
                                    ( leftMatches, rightMatches ) =
                                        findMatches model.cursor swappedBoard

                                    ( scoredBoard, newScore ) =
                                        ( swappedBoard, model.score )
                                            |> Util.Bool.apply
                                                (\( b, s ) ->
                                                    scoreMatch leftMatches b
                                                        |> Tuple.mapSecond ((+) s)
                                                )
                                                (Set.size leftMatches >= 3)
                                            |> Util.Bool.apply
                                                (\( b, s ) ->
                                                    scoreMatch rightMatches b
                                                        |> Tuple.mapSecond ((+) s)
                                                )
                                                (Set.size rightMatches >= 3)
                                in
                                ( { model
                                    | board = scoredBoard
                                    , score = newScore
                                  }
                                , Cmd.none
                                )

                        _ ->
                            ( model, Cmd.none )


dropCells : Board -> Board
dropCells board =
    List.foldl
        (\x brd ->
            List.foldl
                (\y ( b, dropTo ) ->
                    let
                        idx =
                            pointToIndex ( x, y )
                    in
                    case dropTo of
                        Nothing ->
                            case Array.get idx board of
                                Nothing ->
                                    ( b, dropTo )

                                Just cell ->
                                    if cell.symbol == None then
                                        ( b, Just ( cell, idx ) )

                                    else
                                        ( b, dropTo )

                        Just ( cellToPushUp, idxToPushUp ) ->
                            case Array.get idx board of
                                Nothing ->
                                    ( b, Nothing )

                                Just cell ->
                                    ( b
                                        -- TODO: animate down
                                        |> Array.set idxToPushUp cell
                                        |> Array.set idx cellToPushUp
                                    , Just ( cellToPushUp, idx )
                                    )
                )
                ( brd, Nothing )
                (List.range 0 (boardHeight - 1))
                |> Tuple.first
        )
        board
        (List.range 0 (boardWidth - 1))


scoreMatch : Set Point2d -> Board -> ( Board, Int )
scoreMatch cellsToScore board =
    ( Set.foldl
        (\point ->
            Array.Extra.update (pointToIndex point)
                (\cell ->
                    { cell | symbol = None }
                )
        )
        board
        cellsToScore
    , Set.size cellsToScore ^ 2
    )


findMatches : Cursor -> Board -> ( Set Point2d, Set Point2d )
findMatches cursor board =
    let
        leftIdx =
            pointToIndex cursor.left

        rightIdx =
            pointToIndex cursor.right

        leftCell =
            Array.get leftIdx board

        rightCell =
            Array.get rightIdx board
    in
    case ( leftCell, rightCell ) of
        ( Just left, Just right ) ->
            if left.symbol == right.symbol then
                ( Set.empty, Set.empty )

            else
                ( gatherCells left.symbol cursor.left board
                , gatherCells right.symbol cursor.right board
                )

        _ ->
            ( Set.empty, Set.empty )


gatherCells : Symbol -> Point2d -> Board -> Set Point2d
gatherCells originSymbol startPoint board =
    case originSymbol of
        None ->
            Set.empty

        _ ->
            gatherCellsHelper originSymbol (Set.singleton startPoint) board (Set.singleton startPoint) Set.empty


gatherCellsHelper : Symbol -> Set Point2d -> Board -> Set Point2d -> Set Point2d -> Set Point2d
gatherCellsHelper originSymbol nextSearches board gatheredPoints excludedPoints =
    case Set.toList nextSearches of
        [] ->
            gatheredPoints

        ( x, y ) :: restSearches ->
            let
                pointAbove =
                    ( x, y + 1 )

                pointBelow =
                    ( x, y - 1 )

                pointRight =
                    ( if x + 1 == boardWidth then
                        0

                      else
                        x + 1
                    , y
                    )

                pointLeft =
                    ( if x - 1 < 0 then
                        boardWidth - 1

                      else
                        x - 1
                    , y
                    )

                nextNeighbors =
                    [ pointAbove
                    , pointBelow
                    , pointRight
                    , pointLeft
                    ]
                        |> List.filterMap
                            (\point ->
                                if Set.member point gatheredPoints then
                                    Nothing

                                else if Set.member point excludedPoints then
                                    Nothing

                                else
                                    case Array.get (pointToIndex point) board of
                                        Nothing ->
                                            Nothing

                                        Just cell ->
                                            Just
                                                (if cell.symbol == originSymbol then
                                                    Matches point

                                                 else
                                                    Differs point
                                                )
                            )
            in
            case nextNeighbors of
                [] ->
                    gatherCellsHelper originSymbol (Set.fromList restSearches) board gatheredPoints excludedPoints

                neighbors ->
                    let
                        ( rest, gathered, excluded ) =
                            List.foldl
                                (\neighbor ( r, g, e ) ->
                                    case neighbor of
                                        Matches a ->
                                            ( r ++ [ a ], Set.insert a g, e )

                                        Differs a ->
                                            ( r, g, Set.insert a e )
                                )
                                ( restSearches, gatheredPoints, excludedPoints )
                                neighbors
                    in
                    gatherCellsHelper originSymbol (Set.fromList rest) board gathered excluded


type MatchingNeighbor a
    = Matches a
    | Differs a


swapAnimation : Frame3d Length.Meters World Local -> Frame3d Length.Meters World Local -> Animation (Frame3d Length.Meters World Local)
swapAnimation origin destination =
    Animation.animation
        [ { frame = origin
          , offset = 0
          }
        , { frame =
                origin
                    |> Frame3d.translateAlongOwn Frame3d.yAxis
                        (Length.meters (cellSize * 1.5))
          , offset = 30
          }
        , { frame =
                destination
                    |> Frame3d.translateAlongOwn Frame3d.yAxis
                        (Length.meters (cellSize * 1.5))
          , offset = 210
          }
        , { frame = destination
          , offset = 240
          }
        ]


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
        [ Html.h3 []
            [ Html.text "Score:"
            , Html.text (String.fromInt model.score)
            ]
        , Html.div
            [ Html.Attributes.style "border" "1px solid black"
            ]
            [ let
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
              Scene3d.sunny
                { entities =
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
                , dimensions =
                    let
                        desiredWidth =
                            round (toFloat model.windowHeight * 16 / 9)

                        desiredHeight =
                            round (toFloat model.windowWidth * 9 / 16)
                    in
                    if desiredHeight > model.windowHeight then
                        ( Pixels.int desiredWidth
                        , Pixels.int model.windowHeight
                        )

                    else
                        ( Pixels.int model.windowWidth
                        , Pixels.int desiredHeight
                        )
                }
            ]
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
        [ case symbolToColor cell.symbol of
            Just color ->
                Just
                    (Scene3d.block
                        (Scene3d.Material.matte color)
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

            Nothing ->
                Nothing
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


symbolToColor : Symbol -> Maybe Color
symbolToColor symbol =
    case symbol of
        A ->
            Just (Color.rgba 1 0 0 1)

        B ->
            Just (Color.rgba 0 1 0 1)

        C ->
            Just (Color.rgba 0 0 1 1)

        D ->
            Just (Color.rgba 0.5 0 0.5 1)

        None ->
            Nothing
