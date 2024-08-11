- [Description](#description)
- [Usage](#usage)
  - [Tool](#tool)
  - [Framework](#framework)
    - [Payload implementation](#payload-implementation)
    - [Vertices constructing](#vertices-constructing)
  - [Tips](#tips)
- [Internals](#internals)
  - [Overview](#overview)
  - [Vertice processing states](#vertice-processing-states)
  - [{ExcADG::Broker}](#excadgbroker)
  - [{ExcADG::DataStore}](#excadgdatastore)
  - [{ExcADG::StateMachine}](#excadgstatemachine)
  - [{ExcADG::Payload}](#excadgpayload)
  - [{ExcADG::Log}](#excadglog)
  - [{ExcADG::VTracker}](#excadgvtracker)
- [Development](#development)
  - [Gem](#gem)
  - [Testing](#testing)
- [Docs](#docs)
- [Next](#next)
  - [Core](#core)
  - [TUI](#tui)
  - [Payload](#payload)

# Description

That's a library (framework) to execute a graph of dependent tasks (vertices).  
Its main feature is to run all possible tasks independently in parallel once they're ready.  
Another feature is that the graph is dynamic and any vertex could produce another vertice(s) to extend execution graph.

# Usage

## Tool

tl;dr
``` bash
./bin/adgen --range 1:5 --file mygraph.yaml --count 30
./bin/excadg --graph mygraph.yaml -l mygraph.log -d mygraph.yaml --gdump mygraph.jpg
```

There is a tool script in `bin` folder called `excadg`. Run `./bin/excadg --help` for available options.  
It allows to run basic payload graphs specified by a YAML config. See [config/](config/) folder for sample configs.

Another tool is `bin/adgen`, it has `--help` as well. It's suitable to generate relatively complex random graphs.  


## Framework

Main usage pattern for this project is a framework. It implies that you:
- [implement custom payload](#payload-implementation) for vertices
- write a script or extend your program to [construct a swarm vertices](#vertices-constructing) to execute


### Payload implementation

Payload is a piece of code to execute in a single vertex. This code should be self-contained and use specific ways to communicate with other vertices.  
There is a [{ExcADG::Payload}](lib/excadg/payload.rb) module to make a custom payload class. Read through its documentation to get familiar with the interface.  

Here is a very basic example of a payload that echoes a message:

```
class MyPayload
  include ExcADG::Payload
  def get
   lambda { system 'echo here I am' }
  end
end
```
More payload examples could be found in the [{ExcADG::Payload::Example}](lib/excadg/payload/example.rb) module.

Any payload has 3 parts:
- code
- arguments
- dependencies data

**Code** is defined in {ExcADG::Payload#get} method. E.g. `system 'echo here I am'` in the above example.  
**Arguments** could be supplied during payload object contruction (see {ExcADG::Payload#initialize}) as `args:` parameter. E.g. `MyPayload.new args: 'my custom message'`.  
**Dependencies data** is provided by the framework and has all [{ExcADG::VStateData}](lib/excadg/vstate_data.rb) returned by the dependencies.

### Vertices constructing

Vertex is an execution graph's building block. It executes its payload when all its dependencies are finished.  
Vertex can be created this way: `Vertex.new name: :myvertex, payload: MyPayload.new`. This vertex doesn't have any dependencies, so it starts execution immediately upon construction. Vertices without dependencies are always needed in the graph to start it.  

Another "kind" of vertices are vertices with dependencies. Dependencies are an array other vertices that the vertex waits to finish successfully before running its own payload.  

Example:  
`Vertex.new name: :other_vertex, payload: MyPayload.new, deps: [:myvertex]` has exactly 1 dependency - the vertex called `:myvertex`  
`:other_vertex` won't start until `:myvertex` finishes.  
Moreover, as described in [payload](#excadgpayload), `:other_vertex`'s payload will have access to data returned by `:myvertex`'s payload.  
In this case, it'd be what `system 'echo here I am'` returns - `true`.

Dependencies could be specified with both - {ExcADG::Vertex} objects and names. E.g.
``` ruby
Broker.instance.start

v1 = Vertex.new payload: MyPayload.new
Vertex.new name: :v2, payload: MyPayload.new

Vertex.new name: :final, payload: MyPayload.new, deps: [v1, :v2]

Broker.instance.wait_all
```

*See [Broker section](#excadgbroker) for `Broker.instance.start` and `Broker.instance.wait_all` usage.*

Using actual objects looks simpler, but it's less convenient, as it requires you to construct all vertices as they appear in the execution graph.  
However, names allows you to spawn vertices in arbitrary order and expect framework to figure execution order on the fly. See [run tool](#tool)'s code as an example of using names.

*There is no need to store {ExcADG::Vertex} objects, as it and its data are available through [Broker](#excadgbroker)'s [DataStore](#excadgdatastore) and there is no interface to communicate with an {ExcADG::Vertex} directly.*

## Tips

If your app doesn't use all CPU cores with this library or has # of expected vertices much bigger than # of CPUs, try to `export RUBY_MAX_CPU=<num of cores> RUBY_MN_THREADS=1` to engage all cores. *See https://bugs.ruby-lang.org/issues/20618 for details.* 

# Internals

## Overview

This framework allows to spawn vertices. Once created, a vertex with payload starts immediately.
This means that there is no central place that controls execution seqence besides vertex's own mechanism to wait for dependencies.

As Ractors doesn't allow to reliably exchange data between each other at the moment, the main Ractor (thread) has to spawn a broker to synchronize data exchange. See [broker](#excadgbroker) sections to learn more.

This framework is based on [Ractors](https://docs.ruby-lang.org/en/master/ractor_md.html). It could be useful to get familiar with ractors before reading further.

## Vertice processing states

Internally, each vertice go through a sequence of states. Now it's **new**, **ready**, **done** and **failed**. Stages are controlled by the [{ExcADG::StateMachine}](#excadgstatemachine).

{ExcADG::Vertex} starts as a **new** vertex and waits for its dependencies.  
When vertex received all dependencies states and made sure they're **done**, it becomes **ready** and starts its payload.  
When payload finishes, the vertex transitions to the **done** state.  
If any of the stages fails, the vertex becomes **failed**. It could happen as due to a failed dependency (a stage failed) as well as any other error occurred (e.g. it receives an incorrect data from broker). A single failed vertex makes all vertices depending on it to fail. This way [failures cascading through the graph](config/faulty.yaml).

## {ExcADG::Broker}

Broker is a central component meant to receive and transmit data between vertices. There are several [{ExcADG::Request}](lib/excadg/request.rb) types broker supports.

When a vertex changes its state, it (actually, state machine does that) notifies the broker of its state and sends data (results of the transition) ptp the broker. Broker stores this data in a map and could send it to other vertices by request. Vertices polls their dependencies through broker to know where all dependencies are done or some of them failed.

Broker is desired to be as thin as possible to keep most of the work for vertices.

Each application should invoke `Broker.instance.start` to enable messages processing.  
Its counterpart is `Broker.instance.wait_all` which waits for all known vertices to reach one of the terminal states (**done** or **failed**) within specified timeout. Same as `Broker.instance.start`, it spawns a thread and returns it. The main application could keep it in background and query or hang on `.join` once all vertices are spawned. Once the thread finishes, the main app could lookup vertices execution results in `Broker.instance.data_store` (see [DataStore](#excadgdatastore)). Broker could track all the seen vertices and their dependencies using builtin {ExcADG::VTracker}, add `track:true` to the `start` call to enable tracking.

> Note 1: tracking is a purely optional, broker itself requires {ExcADG::DataStore} only  
> Note 2: beware that broker constantly uses main Ractor's ports - incoming and outgoing. Hence, `Ractor#take`, `Ractor.yield` or any other messaging in the main ractor conflict with broker.

## {ExcADG::DataStore}

It's a mostly internal [Broker's](#excadgbroker) object that holds all vertice's [{ExcADG::VStateData}](lib/excadg/vstate_data.rb).

## {ExcADG::StateMachine}

State machine is a small internal mechanism that helps vertices to
- do state transitions
- preserve state transition results locally

State machine has transitions graph that is common for all vertices. Vertices bind certain logic to transitions. E.g. "wait for dependencies" or "run the payload". State transition mechanism ensures to run workload associated to the currently possible transition, process errors (if any) and send results to [Broker](#excadgbroker).

## {ExcADG::Payload}

Payload is a special module that carries convention for Vertex-es payload. Only classes that `include ExcADG::Payload` are expected to be providede as payload during vertex creation. _Although, obviously, there are dozens of ways to trick the code._

Payload existence is caused by that Ractors require all objects a Ractor uses to be moved (or copied) to it. A pure {ExcADG::Proc} can't be transferred, as it doesn't have allocator and can access outer scope (which has to be transferred too then), what could be impossible due to other non-shareable objects there.

To make the interface clearer and more reliable, Payload encloses a `Proc` within its `get` method. As isolated `Proc`s are not useful most of the time, Payload has 2 ways to provide/access the needful for payload to work.  
First way is `args` parameter of the {Payload#initialize}. It can be used on payload creation time to customize payload's behavior. The paremeter is accessible within the labmda through `@args` attribute.  
Second way is built-in. Vertex invokes payload with {ExcADG::Array} of dependencies {ExcADG::VStateData}, if payload's `Proc` is parametrized (has arity 1).

> Be mindful about data your payload receives (args) and returns (state data). It could appear incompatible with ractors and cause vertice to fail.  
> Although these failures are hard to tell beforehand, [state machine](#excadgstatemachine) processes them gracefully.

## {ExcADG::Log}

The library has its own logger based on Ractors. You could call {ExcADG::Log#unmute} to enable these logs.

## {ExcADG::VTracker}

It's an optional component which allows to track all vertices to be able to repro the full graph. There is no central place that stores the whole graph due to the ExcADG's core princilple - allow to spawn vertices at any time from any place. This class is introduced in order to support doing basic execution visualization (see {ExcADG::Tui}) and analysis.

The tracker is integrated to the Broker and can be accessed by `ExcADG::Broker.instance.vtracker`. It's disabled by default to speed-up execution, but can be enabled on borker's startup by `Broker.instance.start track: true`.

# Development

The project is based on RVM => there is a .ruby-gemset file.  
Bundler is configured to install gems for dev environment, use `bundle install --without dev` to install only modules needed to run the code.

## Gem

There is a gem specification. Typical commands:
- build gem: `gem build excadg.gemspec`
- install / uninstall gem built locally: `gem install ./excadg*.gem` / `gem uninstall excadg`
- publish: `gem push excadg*.gem`

Latest version is published here: https://rubygems.org/gems/excadg.

## Testing

Test are located in [spec/](spec/) folder and are written using rspec.

Commands to run tests:
- `rspec` - run most of the tests
- `rspec spec/broker_spec.rb` - run tests from the file
- `rspec spec/broker_spec:32` - run tests that starts on line 32 of the file
- `rspec --tag perf` - run tests of a specific suite

  > there is no consistent set of suites, tags are used to exclude mutually incompatible tests or e.g. perfomance tests  
  > search for `config.filter_run_excluding` in [spec/spec_helper.rb](spec/spec_helper.rb) to see what tests are disabled by default

Logging is disabled by default, but it could be useful to debug tests. Add `ExcADG::Log.unmute` to `spec/spec_helper.rb` to enable logs.

# Docs

`yard doc lib/` generates a descent documentation.

`yard server --reload` starts a server with documentation available at http://localhost:8808

# Next

> here is a list of improvemets could be implementex next

## Core
1. implement throttling: allow to `:suspend` vertices that polls deps
  - limit # of simultaneously running vertices
  - limit # of vertices allowed to spawn
2. implement checks using tracker
  - for loops (it also leads to cases when there are no nodes to start from)
  - for unreachable islands (optional, it could be expected)
  - for the failure root cause
3. move Vertice's tests to system test suite, make UTs for Vertice class

## TUI
1. make timeouts more flexible in the excadg tool
2. allow to focus on a certain vertex to see what's it waiting for and what's waiting for it
3. allow to dump focused vertice's state
4. improve messages for timed out execution
5. split TUI to another gem

## Payload
4. make a loop payload template
5. allow to stream shell payload stdout/err in realtime to logs and files
6. add native ruby example with a dynamic graph