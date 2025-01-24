module Main exposing (..)

import Angle
import Array exposing (Array)
import Axis3d
import Block3d
import Browser
import Camera3d
import Color exposing (Color)
import Direction3d
import Length
import Pixels
import Point3d
import Random
import Random.List
import Scene3d
import Scene3d.Material
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


type alias Board =
    Array Cell


type alias Cell =
    { symbol : Symbol
    , animating : Animating
    }


type Animating
    = Down
    | Left
    | Right
    | None


type Symbol
    = A
    | B
    | C
    | D


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
                                    , animating = None
                                    }
                                )
                            )
                            >> Array.fromList
                        )
                )
                (Random.initialSeed seedStarter)
    in
    ( { seed = seed
      , board = initialBoard
      }
    , Cmd.none
    )


type Msg
    = NoOp


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )


type alias Point2d =
    ( Int, Int )


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
                            , azimuth = Angle.degrees 0
                            , elevation = Angle.degrees 5
                            , distance = Length.meters 30
                            }
                    , verticalFieldOfView = Angle.degrees 30
                    }
          in
          -- Render a scene that doesn't involve any lighting (no lighting is needed
          -- here since we provided a material that will result in a constant color
          -- no matter what lighting is used)
          Scene3d.sunny
            { -- Our scene has a single 'entity' in it
              entities =
                model.board
                    |> Array.toList
                    |> List.indexedMap viewCell
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


viewCell : Int -> Cell -> Scene3d.Entity coordinates
viewCell index cell =
    let
        ( x, y ) =
            indexToPoint index
    in
    Scene3d.block
        (Scene3d.Material.matte (symbolToColor cell.symbol))
        (Block3d.with
            { x1 = Length.meters (cellSize / -2)
            , x2 = Length.meters (cellSize / 2)
            , y1 = Length.meters (cellSize / -2)
            , y2 = Length.meters (cellSize / 2)
            , z1 = Length.meters (cellSize / -2)
            , z2 = Length.meters (cellSize / 2)
            }
            |> Block3d.translateBy (Vector3d.meters 0 radius (toFloat y))
            |> Block3d.rotateAround
                Axis3d.z
                (Angle.degrees (rotationDeg * toFloat x))
        )


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
