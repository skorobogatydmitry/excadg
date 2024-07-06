# Description

That's a library (framework) to execute a graph of dependent tasks (vertices).  
Its main feature is to run all possible tasks independently in parallel once they're ready.  
Another feature is that the graph is dynamic and any vertex could produce another vertice(s) to extend execution graph.

# Usage

## Tool

There is a tool script in root folder called `excadg`. Run `./bin/excadg --help` for available options.  
It allows to make and run basic payload graphs specified by a YAML config. See [config/](config/) folder for sample configs.

## Framework

Main usage pattern for this project is a framework. It implies that you:
- [implement custom payload](#payload-implementation) for vertices
- write a script or extend your program to [construct a swarm vertices](#vertices-constructing) to execute


### Payload implementation

Payload is a piece of code to execute in a single vertex. This code should be self-contained and use specific ways to communicate with other vertices.  
There is a [{ExcADG::Payload}](lib/excadg/payload.rb) module to make a custom payload class. Read through its documentation to get familiar with its interface.  

Here is a very basic example of a payload that echoes a message:

```
class MyPayload
  include ExcADG::Payload
  def get
   lambda { system 'echo here I am' }
  end
end
```
More payload examples could be found in [{ExcADG::Payload::Example}](lib/excadg/payload/example.rb).

Any payload has 3 parts:
- code
- arguments
- dependencies data

**Code** is defined in {Payload#get} method. E.g. `system 'echo here I am'` in the above example.  
**Arguments** are defined during payload object contruction (see {Payload#initialize}) as `args:` parameter. E.g. `MyPayload.new args: 'my custom message'`.  
**Dependencies data** is provided by the framework and has all [{ExcADG::VStateData}](lib/excadg/vstate_data.rb) returned by the dependencies.

### Vertices constructing

Vertex is a execution graph's building block. It executes its payload when all its dependencies are finished.  
Vertex can be created this way: `Vertex.new name: :myvertex, payload: MyPayload.new`. This vertex doesn't have any dependencies, so it starts execution immediately upon construction. Vertices without dependencies are always aneeded in the graph to start it.  

Another "kind" of vertices are vertices with dependencies. Dependencies are other vertices that the vertex waits to finish successfully before running its own payload.  
> Example: `Vertex.new name: :other_vertex, payload: MyPayload.new, deps: [:myvertex]` has exactly 1 dependency - vertex called `:myvertex`  
> `:other_vertex` won't start until `:myvertex` finishes.  
> Moreover, as described in [payload](#payload), `:other_vertex`'s payload will have access to data returned by `:myvertex`'s payload.  
> In this case, it'd be what `system 'echo here I am'` returns - `true`.

Dependencies could be specified both - using {ExcADG::Vertex} objects and names. E.g.
``` ruby
Broker.run

v1 = Vertex.new payload: MyPayload.new
Vertex.new name: :v2, payload: MyPayload.new

Vertex.new name: :final, payload: MyPayload.new, deps: [v1, :v2]

Broker.wait_all
```

*See [Broker section](#broker) for `Broker.run` and `Broker.wait_all` usage.*

Using actual objects looks simpler, but it's less convenient, as it requires you to construct all vertices as they appear in the execution graph.  
However, names allows you to spawn vertices in arbitrary order and expect framework to figure execution order on the fly. See [run tool](#tool) as an example of using names.

*There is no need to store {ExcADG::Vertex} objects, as it and its data are available through [Broker](#broker)'s [DataStore](#data-store) and there is no interface to communicate with a {ExcADG::Vertex} directly.*

# Internals

## Overview

This framework allows to spawn vertices. Once created, a vertex with payload starts immediately.
This means that there is no central place where execution seqence is controlled besides vertex's own mechanism to wait for dependencies.

As Ractors doesn't allow to reliably exchange data between each other at the moment, the main Ractor (thread) has to spawn a broker to synchronize data exchange. See [broker](#broker) sections to learn more.

This framework is based on [Ractors](https://docs.ruby-lang.org/en/master/ractor_md.html). It could be useful to get familiar with ractors before reading further.

## Vertice processing states

Internally, each vertice goes through a sequence of states. Now it's **new**, **ready**, **done** and **failed**. Stages are controlled by the [{ExcADG::StateMachine}](#statemachine).

{ExcADG::Vertex} starts as a **new** vertex and waits for its dependencies.  
When vertex received all dependencies states and made sure they're **done**, it becomes **ready** and starts its payload.  
When payload finishes, the vertex transitions to the **done** state.  
If any of the stages fails, the vertex becomes **failed**. It could happen as due to a failed dependency (a stage failed) as well as any other error occurred (e.g. it receives an incorrect data from broker). A single failed vertex makes all vertices depending on it to fail. This way a failures cascading through the graph.

## {ExcADG::Broker}

Broker is a central component meant to receive and transmit data between vertices. There are several [{ExcADG::Request}](lib/excadg/request.rb) types broker supports.

When a vertex changes its state, it (actually, state machine does that) notifies the broker of its state and sends data (results of the transition) ptp the broker. Broker stores this data in a map and could send it to other vertices by request. Vertices polls their dependencies through broker to know where all dependencies are done or some of them failed.

Broker is desired to be as thin as possible to keep most of the work for vertices.

Each application should invoke {Broker.run} to enable messages processing.  
Its counterpart is {Broker.wait_all} which waits for all known vertices to reach one of the terminal states (**done** or **failed**) within specified timeout. Same as `Broker.run`, it spawns a thread and returns it. The main application could keep it in background and query or `.join` on it once all vertices are spawned. Once the thread finishes, the main app could lookup vertices execution results in {Broker.data_store} (see [DataStore](#data-store)).

> Beware that broker constantly uses main Ractor's ports - incoming and outgoing. Hence, `Ractor#take`, `Ractor.yield` or any other messaging in the main ractor conflict with broker.

## {ExcADG::DataStore}

It's a mostly internal [Broker's](#broker) object that holds all vertice's [{ExcADG::VStateData}](lib/excadg/vstate_data.rb).

## {ExcADG::StateMachine}

State machine is a small internal mechanism that helps vertices to
- do state transitions
- preserve state transition results locally

State machine has transitions graph that is common for all vertices. Vertices bind certain logic to transitions. E.g. "wait for dependencies" or "run the payload". State transition mechanism ensures to run workload associated to the currently possible transition, process errors (if any) and send results to [Broker](#broker).

## {ExcADG::Payload}

Payload is a special module that carries convention for Vertex-es payload. Only classes that `include ExcADG::Payload` are expected to be providede as payload during vertex creation. _Although, obviously, there are dozens of ways to trick the code._

Payload existence is caused by that Ractors require all objects a Ractor uses to be moved (or copied) to it. A pure {ExcADG::Proc} can't be transferred, as it doesn't have allocator and can access outer scope (which has to be transferred too then), what could be impossible due to other non-shareable objects there.

To make the interface clearer and more reliable, Payload encloses a `Proc` within its `get` method. As isolated `Proc`s are not useful most of the time, Payload has 2 ways to provide/access the needful for payload to work.  
First way is `args` parameter of the {Payload#initialize}. It can be used on payload creation time to customize payload's behavior. The paremeter is accessible within the labmda through `@args` attribute.  
Second way is built-in. Vertex invokes payload with {ExcADG::Array} of dependencies {ExcADG::VStateData}, if payload's `Proc` is parametrized (has arity 1).

> Be mindful about data your payload receives (args) and returns (state data). It could appear incompatible with ractors and cause vertice to fail.  
> Although these failures are hard to tell beforehand, [state machine](#statemachine) processes them gracefully.

# Development

The project is based on RVM => there is a .ruby-gemset file.  
Bundler is configured to install gems for dev environment, use `bundle install --without dev` to install only modules needed to run the code.

# Testing

Test are located in [spec/](spec/) folder and are written using rspec.

Commands to run tests:
- `rspec` - run most of the tests
- `rspec spec/broker_spec.rb` - run tests from the file
- `rspec spec/broker_spec:32` - run tests that starts on line 32 of the file
- `rspec --tag perf` - run tests of a specific suite

  > there is no consistent set of suites, tags are used to exclude mutually incompatible tests or e.g. perfomance tests  
  > search for `config.filter_run_excluding` in [spec/spec_helper.rb](spec/spec_helper.rb) to see what tests are disabled by default

## Logging

Most of the tests have loggin stubbed to avoid noize. Comment out either `stub_loogging` or `Log.mute` in the respective spec file to enable logging for it.

# Docs

`yard doc lib/` generates a descent documentation.

`yard server --reload` starts a server with documentation available at http://localhost:8808

# Next

> here is a list of improvemets could be implementex next

- make a root module
- make a gem
- add timeouts
  - to payload
  - to the whole vertex
  - to request processing
- implement throttling (:suspended state)
  - limit # of running vertices
    - problem: can't find what to suspend
- make a loop payload template
  - provide a mechanism to control # of children

## Graph checks

  - check for loops in the config
  - check for unreachable islands - graph connectivity
  - check that there are nodes to start from