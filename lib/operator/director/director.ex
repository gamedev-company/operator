defmodule Operator.Director do
  @moduledoc """
  Narrative orchestration system for dynamic event generation.

  The Director is a GenServer that acts as your game's "AI Director" (inspired
  by Left 4 Dead's famous system). It monitors world state and decides when
  interesting events should occur, controlling narrative pacing and dramatic
  tension.

  ## The Director Pattern

  ```
  ┌─────────────────────────────────────────────────────────────────┐
  │                        Game Loop                                 │
  │   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
  │   │ Update NPCs │ --> │ Physics/AI  │ --> │ Render      │       │
  │   └─────────────┘     └─────────────┘     └─────────────┘       │
  │         │                                                        │
  │         │ world_state                                            │
  │         ▼                                                        │
  │   ┌─────────────────────────────────────┐                       │
  │   │           Director                  │                       │
  │   │  ┌─────────────────────────────┐    │                       │
  │   │  │      Storyteller            │    │     ┌──────────────┐  │
  │   │  │  - monitors tension         │----│---> │ Game Events  │  │
  │   │  │  - picks event timing       │    │     │ (spawn enemy,│  │
  │   │  │  - controls pacing          │    │     │  trigger     │  │
  │   │  └─────────────────────────────┘    │     │  dialogue)   │  │
  │   └─────────────────────────────────────┘     └──────────────┘  │
  └─────────────────────────────────────────────────────────────────┘
  ```

  ## Quick Start

      # 1. Define your storyteller
      defmodule MyGame.TensionStoryteller do
        @behaviour Operator.Storyteller

        @impl true
        def init(_opts), do: %{last_event_tick: 0}

        @impl true
        def pick_event(tick, world_state, state) do
          tension = Map.get(world_state, :tension, 0.0)

          if tension > 0.7 and tick - state.last_event_tick > 100 do
            event = %{type: :ambush, location: pick_location(world_state)}
            {event, %{state | last_event_tick: tick}}
          else
            {nil, state}
          end
        end
      end

      # 2. Start the Director
      {:ok, _pid} = Operator.Director.start_link(
        storyteller: MyGame.TensionStoryteller,
        on_event: &MyGame.EventHandler.process/1
      )

      # 3. Feed it world state each tick
      def game_tick(world_state) do
        Operator.Director.tick(world_state)
        # ... rest of game loop
      end

  ## Startup Options

  * `:storyteller` - Module implementing `Operator.Storyteller`
    (default: `NullStoryteller`)
  * `:name` - GenServer name (default: `Operator.Director`)
  * `:on_event` - Callback `fn event -> :ok end` for generated events

  ## Event Flow

  1. Your game calls `Director.tick(world_state)` each simulation tick
  2. Director invokes `storyteller.pick_event(tick, world_state, state)`
  3. If the storyteller returns an event, Director:
     - Rationalizes it via `Operator.Rationalization`
     - Emits telemetry via `Operator.Telemetry`
     - Calls your `:on_event` callback
  4. Your game reacts to the event (spawn enemies, trigger dialogue, etc.)

  ## Runtime Control

      # Change storytellers based on game phase
      Operator.Director.change_storyteller(MyGame.BossFightStoryteller)

      # Get current tick for synchronization
      current_tick = Operator.Director.current_tick()

      # Debug storyteller state
      state = Operator.Director.get_state()

  ## Integration Philosophy

  The Director is intentionally lightweight. It does NOT:

  * Subscribe to PubSub topics
  * Persist events to timelines
  * Handle clustering

  These concerns belong to your host application. The Director's job is
  purely to decide **when** and **what** events to generate.

  ## Synchronous Testing

  For tests, use `tick_sync/2` to get immediate results:

      event = Operator.Director.tick_sync(world_state)
      assert event.type == :ambush

  ## See Also

  * `Operator.Storyteller` - Behaviour for storyteller modules
  * `Operator.Director.NullStoryteller` - No-op storyteller for testing
  * `Operator.Rationalization` - Event annotation

  """

  use GenServer

  require Logger

  alias Operator.Director.NullStoryteller
  alias Operator.{Rationalization, Telemetry}

  defstruct [
    :tick,
    :storyteller,
    :last_event_tick,
    :on_event
  ]

  @type storyteller_state :: {module(), map()}

  @type t :: %__MODULE__{
          tick: non_neg_integer(),
          storyteller: storyteller_state(),
          last_event_tick: non_neg_integer(),
          on_event: (map() -> :ok) | nil
        }

  # Public API

  @doc """
  Start the Director.

  ## Options

  - `:storyteller` - Storyteller module (default: NullStoryteller)
  - `:name` - GenServer name (default: Operator.Director)
  - `:on_event` - Callback for generated events

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    storyteller_module = Keyword.get(opts, :storyteller, NullStoryteller)
    name = Keyword.get(opts, :name, __MODULE__)
    on_event = Keyword.get(opts, :on_event)

    GenServer.start_link(__MODULE__, {storyteller_module, on_event}, name: name)
  end

  @doc """
  Get the current tick.
  """
  @spec current_tick(GenServer.server()) :: non_neg_integer()
  def current_tick(server \\ __MODULE__) do
    GenServer.call(server, :current_tick)
  end

  @doc """
  Change the active storyteller at runtime.
  """
  @spec change_storyteller(module(), GenServer.server()) :: :ok
  def change_storyteller(new_storyteller_module, server \\ __MODULE__) do
    GenServer.call(server, {:change_storyteller, new_storyteller_module})
  end

  @doc """
  Get the current state (for debugging).
  """
  @spec get_state(GenServer.server()) :: t()
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Trigger a tick with the given world state.

  Call this from your simulation's tick handler.
  """
  @spec tick(map(), GenServer.server()) :: :ok
  def tick(world_state, server \\ __MODULE__) do
    GenServer.cast(server, {:tick, world_state})
  end

  @doc """
  Synchronous tick that returns any generated event.

  Useful for testing.
  """
  @spec tick_sync(map(), GenServer.server()) :: map() | nil
  def tick_sync(world_state, server \\ __MODULE__) do
    GenServer.call(server, {:tick_sync, world_state})
  end

  # GenServer Callbacks

  @impl true
  def init({storyteller_module, on_event}) do
    storyteller_state = storyteller_module.init(%{})

    state = %__MODULE__{
      tick: 0,
      storyteller: {storyteller_module, storyteller_state},
      last_event_tick: 0,
      on_event: on_event
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:change_storyteller, new_module}, _from, state) do
    new_st_state = new_module.init(%{})
    {:reply, :ok, %{state | storyteller: {new_module, new_st_state}}}
  end

  @impl true
  def handle_call({:tick_sync, world_state}, _from, state) do
    {event, new_state} = do_tick(world_state, state)
    {:reply, event, new_state}
  end

  @impl true
  def handle_cast({:tick, world_state}, state) do
    {_event, new_state} = do_tick(world_state, state)
    {:noreply, new_state}
  end

  # Private helpers

  defp do_tick(world_state, state) do
    tick = Map.get(world_state, :tick, state.tick + 1)
    {mod, st_state} = state.storyteller

    {event, new_st_state} = mod.pick_event(tick, world_state, st_state)

    {rationalized, last_event_tick} =
      case event do
        nil ->
          {nil, state.last_event_tick}

        raw_event ->
          processed = process_event(raw_event, tick, state)
          {processed, tick}
      end

    new_state = %{
      state
      | tick: tick,
        storyteller: {mod, new_st_state},
        last_event_tick: last_event_tick
    }

    {rationalized, new_state}
  end

  defp process_event(event, tick, state) do
    # Ensure tick is set
    event = Map.put_new(event, :tick, tick)

    # Rationalize the event
    rationalized = Rationalization.apply(event)

    # Emit telemetry
    event_type = Map.get(rationalized, :type, :unknown)
    Telemetry.emit_director_event(event_type, tick)

    # Call on_event callback if provided
    if state.on_event do
      state.on_event.(rationalized)
    end

    rationalized
  end
end
