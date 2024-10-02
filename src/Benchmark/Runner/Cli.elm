module Benchmark.Runner.Cli exposing
    ( program
    , Output
    , Model, Msg
    )

{-| This module provides a way to run benchmarks in a CLI environment.

@docs program
@docs Output
@docs Model, Msg

-}

import Benchmark exposing (Benchmark)
import Benchmark.Status.Alternative as Status
import Task
import Trend.Linear as Trend


{-| Model for the benchmark runner.
-}
type alias Model =
    { suite : Benchmark
    , sendOutput : Output -> Cmd Msg
    }


{-| Msg for the benchmark runner.
-}
type Msg
    = BenchmarkProgress Benchmark


{-| Benchmark results, ready to be sent via port to the parent program.

The result names will contain the path to the benchmark (through all the `Benchmark.describe` groups etc.).

To get runs/second, you can use the following formula: `1e9 / nsPerRun`.

The warning, if present, will be about low goodness of fit (<0.95 and <0.85).

-}
type alias Output =
    { warning : Maybe String
    , results :
        List
            { name : List String
            , nsPerRun : Maybe Float
            }
    }


{-| Run benchmarks.

    port sendOutput : Benchmark.Runner.Cli.Output -> Cmd msg

    main =
        Benchmark.Runner.Cli.program
            { suite = suite
            , sendOutput = sendOutput -- your port!
            }

-}
program : Model -> Platform.Program () Model Msg
program model =
    Platform.worker
        { init =
            \() ->
                ( model
                , Task.succeed model.suite
                    |> Task.perform BenchmarkProgress
                )
        , update = update
        , subscriptions = \_ -> Sub.none
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update (BenchmarkProgress updatedSuite) model =
    let
        newModel =
            { model | suite = updatedSuite }
    in
    ( newModel
    , progressBenchmark newModel
    )


{-| `Benchmark.step` if the benchmark still hasn't received all results.
-}
progressBenchmark : Model -> Cmd Msg
progressBenchmark model =
    case Status.fromBenchmark model.suite of
        Status.Running _ _ ->
            Benchmark.step model.suite
                |> Task.perform BenchmarkProgress

        Status.Finished finished ->
            model.sendOutput
                { warning = viewWarning finished
                , results = getResults finished
                }


getResults : Status.Structure { result : Status.Result } -> List { name : List String, nsPerRun : Maybe Float }
getResults finished =
    case finished.structureKind of
        Status.Group group ->
            group
                |> List.concatMap
                    (getResults
                        >> List.map
                            (\{ name, nsPerRun } ->
                                { name = finished.name :: name
                                , nsPerRun = nsPerRun
                                }
                            )
                    )

        Status.Single { result } ->
            [ { name = [ finished.name ]
              , nsPerRun = nanosecondsPerRun result
              }
            ]

        Status.Series series ->
            series
                |> List.map
                    (\{ name, result } ->
                        { name = [ finished.name, name ]
                        , nsPerRun = nanosecondsPerRun result
                        }
                    )


nanosecondsPerRun : Status.Result -> Maybe Float
nanosecondsPerRun result =
    case result of
        Ok trend ->
            let
                { slope, intercept } =
                    Trend.line trend
            in
            -- Derived from `1e9 / Trend.predictX (Trend.line trend) 1e3`
            Just <| 1.0e9 * slope / (1.0e3 - intercept)

        Err _ ->
            Nothing


viewWarning : Status.Structure { result : Status.Result } -> Maybe String
viewWarning finished =
    let
        minimumGoodnessOfFit : Float
        minimumGoodnessOfFit =
            finished
                |> Status.results
                |> List.filterMap Result.toMaybe
                |> List.map Trend.goodnessOfFit
                |> List.minimum
                |> Maybe.withDefault 1
    in
    -- https://github.com/elm-explorations/benchmark/issues/4#issuecomment-388401035
    if minimumGoodnessOfFit < 0.85 then
        Just "There is high interference on the system. Don't trust these results. Close resource-intensive tabs or programs (Slack, Spotify are typical candidates) and run again. If that doesn't solve it, show up in #elm-benchmark on the Elm Slack and we'll try to get you sorted out. There's probably some error this tool can't detect, or we need to account for your system setup in the sampling approach."

    else if minimumGoodnessOfFit < 0.95 then
        Just "There may be interference on the system. Consider closing resource-intensive programs (Slack, Spotify are typical candidates) or tabs and run again."

    else
        Nothing
