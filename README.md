# elm-benchmark-cli-runner

Allows running [elm-explorations/benchmark](https://package.elm-lang.org/packages/elm-explorations/benchmark/latest/) benchmarks in CLI, getting results back via port:

```elm
import Benchmark.Runner.Cli

port sendOutput : Benchmark.Runner.Cli.Output -> Cmd msg
```

⬇️

```javascript
app.ports.sendOutput.subscribe((output) => {
    console.log(JSON.stringify(output, null, 2));
});
```

⬇️

```json
{
  "results": [
    { "name": [ "remove", "listRemoveOld" ], "nsPerRun": 561.8524436770276 },
    { "name": [ "remove", "listRemoveNew" ], "nsPerRun": 573.8985643419595 }
  ],
  "warning": null
}
```
