defmodule Operator.Director.NullStoryteller do
  @moduledoc """
  A storyteller that never generates events.

  Useful for testing or when you want the Director running
  but don't need automatic event generation.
  """

  @behaviour Operator.Storyteller

  @impl true
  def init(_opts), do: %{}

  @impl true
  def pick_event(_tick, _world_state, state), do: {nil, state}
end
