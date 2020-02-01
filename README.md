Issue: https://github.com/dotnet/runtime/issues/31613

Hi.

I saw a performance regression going from .NET 4.8 to dotnet core 3.1. It's small so in practice this might not hurt most users but I thought it's better to create an issue than keeping mum.

I noticed it when discussing my other issue: https://github.com/dotnet/runtime/issues/2191 so the code will be similar although I don't think this is tail call related but I don't know for sure of course.

When setting up a simple push stream pipeline

```fsharp
// Minimalistic PushStream
//  A PushStream accepts a receiver function that will be called
//  with each value in the PushStream
type 'T PushStream = ('T -> unit) -> unit

module PushStream =
  let inline zero      ()       = LanguagePrimitives.GenericZero
  let inline push      r v      = r v

  // Creates a PushStream with all integers from b to e (inclusive)
  let inline fromRange b e    r = for i = b to e do push r i
  // Maps all values in ps using mapping function f
  let inline map       f   ps r = ps (fun v -> push r (f v))
  // Filters all values in ps using filter function f
  let inline filter    f   ps r = ps (fun v -> if f v then push r v)
  // Sums all values in ps
  let inline sum           ps   = let mutable s = zero () in ps (fun v -> s <- s + v); s

[<DisassemblyDiagnoser>]
type Benchmarks () =
  [<Params (10000, 100)>]
  member val public Count = 100 with get, set

  [<Benchmark>]
  member x.SimplePushStreamTest () =
    PushStream.fromRange  0 x.Count
    |> PushStream.map     int64
    |> PushStream.filter  (fun v -> (v &&& 1L) = 0L)
    |> PushStream.map     ((+) 1L)
    |> PushStream.sum
```

Benchmark dotnet reports:

```
$ dotnet run -c Release -f netcoreapp3.1 --filter '*' --runtimes net48 netcoreapp3.1
...
|               Method |       Runtime |     Toolchain | Count |        Mean |     Error |    StdDev | Ratio | RatioSD | Code Size |
|--------------------- |-------------- |-------------- |------ |------------:|----------:|----------:|------:|--------:|----------:|
| SimplePushStreamTest |      .NET 4.8 |         net48 |   100 |    400.6 ns |   3.92 ns |   3.67 ns |  1.00 |    0.00 |     272 B |
| SimplePushStreamTest | .NET Core 3.1 | netcoreapp3.1 |   100 |    439.3 ns |   4.35 ns |   4.07 ns |  1.10 |    0.02 |     273 B |
|                      |               |               |       |             |           |           |       |         |           |
| SimplePushStreamTest |      .NET 4.8 |         net48 | 10000 | 33,542.5 ns | 143.25 ns | 133.99 ns |  1.00 |    0.00 |     272 B |
| SimplePushStreamTest | .NET Core 3.1 | netcoreapp3.1 | 10000 | 39,449.8 ns | 259.08 ns | 242.35 ns |  1.18 |    0.01 |     273 B |
```

.NET 4.8 performs between 10% to 20% faster than dotnet core 3.1.

I dug a bit into the jitted assembler and found the following differences

```diff
--- dotnetcore.asm
+++ net48.asm
@@ -1,4 +1,4 @@
-; dotnet core 3.1
+; .net v48

 ; PushStream.fromRange  0 x.Count
 LOOP:
@@ -12,7 +12,6 @@
 jne     LOOP

 ; PushStream.map     int64
-nop     dword ptr [rax+rax]
 mov     rcx,qword ptr [rcx+8]
 movsxd  rdx,edx
 mov     rax,qword ptr [rcx]
@@ -21,8 +20,7 @@
 jmp     rax

 ; PushStream.filter  (fun v -> (v &&& 1L) = 0L)
-nop     dword ptr [rax+rax]
-mov     eax,edx
+mov     rax,rdx
 test    al,1
 jne     BAILOUT
 mov     rcx,qword ptr [rcx+8]
@@ -35,7 +33,6 @@
 ret

 ; PushStream.map     ((+) 1L)
-nop     dword ptr [rax+rax]
 mov     rcx,qword ptr [rcx+8]
 inc     rdx
 mov     rax,qword ptr [rcx]
@@ -44,11 +41,9 @@
 jmp     rax

 ; PushStream.sum
-nop     dword ptr [rax+rax]
 mov     rax,qword ptr [rcx+8]
 mov     rcx,rax
 add     rdx,qword ptr [rax+8]
 mov     qword ptr [rcx+8],rdx
 xor     eax,eax
 ret
-
```

It seems that in dotnet core there's an extra nop at the start of each method. I suspected tiered compilation but after much messing about trying to disable tiered compilation it's either unrelated or I wasn't able to disable tiered compilation.

It surprises me that the nop adds this much overhead but I can't spot anything else of significance.

The code is here: https://github.com/mrange/TryNewDisassembler/tree/fsharpPerformanceRegression

And here:

```fsharp
module PerformanceRegression =
  open System
  open System.Linq
  open System.Diagnostics

  // Minimalistic PushStream
  //  A PushStream accepts a receiver function that will be called
  //  with each value in the PushStream
  type 'T PushStream = ('T -> unit) -> unit

  module PushStream =
    let inline zero      ()       = LanguagePrimitives.GenericZero
    let inline push      r v      = r v

    // Creates a PushStream with all integers from b to e (inclusive)
    let inline fromRange b e    r = for i = b to e do push r i
    // Maps all values in ps using mapping function f
    let inline map       f   ps r = ps (fun v -> push r (f v))
    // Filters all values in ps using filter function f
    let inline filter    f   ps r = ps (fun v -> if f v then push r v)
    // Sums all values in ps
    let inline sum           ps   = let mutable s = zero () in ps (fun v -> s <- s + v); s

  module Tests =
    open BenchmarkDotNet.Attributes
    open BenchmarkDotNet.Configs
    open BenchmarkDotNet.Jobs
    open BenchmarkDotNet.Horology
    open BenchmarkDotNet.Running
    open BenchmarkDotNet.Diagnostics.Windows.Configs

    [<DisassemblyDiagnoser>]
    type Benchmarks () =
      [<Params (10000, 100)>]
      member val public Count = 100 with get, set

      [<Benchmark>]
      member x.SimplePushStreamTest () =
        PushStream.fromRange  0 x.Count
        |> PushStream.map     int64
        |> PushStream.filter  (fun v -> (v &&& 1L) = 0L)
        |> PushStream.map     ((+) 1L)
        |> PushStream.sum

    let run argv =
      let job = Job.Default
                    .WithWarmupCount(30)
                    .WithIterationTime(TimeInterval.FromMilliseconds(250.0)) // the default is 0.5s per iteration, which is slighlty too much for us
                    .WithMinIterationCount(15)
                    .WithMaxIterationCount(20)
                    .AsDefault()
      let config = DefaultConfig.Instance.AddJob(job)
      let b = BenchmarkSwitcher [|typeof<Benchmarks>|]
      let summary = b.Run(argv, config)
      printfn "%A" summary

// Run with: dotnet run -c Release -f netcoreapp3.1 --filter '*' --runtimes net48 netcoreapp3.1
[<EntryPoint>]
let main argv =
  PerformanceRegression.Tests.run argv
  0
```