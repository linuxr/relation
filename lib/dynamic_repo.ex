defmodule Relation.DynamicRepo do

  defmacro __using__(_opts) do
    m = Application.get_env(:relation, :repo)

    quote do
      alias unquote(m), as: Repo
    end
  end
end
