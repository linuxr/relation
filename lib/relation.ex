defmodule Relation do
  @moduledoc """
  Common relation operations for Relational database(mysql, postgresql, etc...),
  You could build rest api base on it.
  """
  alias Ecto.Multi
  alias Building.Repo
  import Ecto.Query

  require Logger

  @doc """
  Under score.

  """
  defp underscore(model_str), do: Macro.underscore(model_str)

  @doc """
  Convert relations.

  """
  defp convert_relations(relations) do
    relations
    |> Enum.map(&convert_model/1)
  end

  defp convert_model(params) when is_map(params) do
    params
    |> update_model("model", &underscore/1)
    |> update_model("from_model", &underscore/1)
    |> update_model("to_model", &underscore/1)
    |> update_model("relations", &convert_relations/1)
  end

  defp convert_model(params) when is_binary(params) do
    underscore(params)
  end

  defp convert_model(params), do: params

  defp update_model(params, key, convert_fn) do
    case Map.pop(params, key) do
      {nil, params} -> params
      {val, params} -> Map.put(params, key, convert_fn.(val))
    end
  end

  @doc """
  Dispatch action.

  ## Examples

  iex> Relation.action_dispatch(params)
  {json result}

  """
  def action_dispatch(params) do
    Logger.debug("params before convert: #{inspect(params)}")
    params = convert_model(params)
    Logger.debug("params after convert: #{inspect(params)}")
    case params do
      %{"action" => "create"} ->
        create(params)
      %{"action" => "delete"} ->
        delete(params)
      %{"action" => "update"} ->
        update(params)
      %{"action" => "query"} ->
        query(params)
    end
  end

  # create
  def create(params) do
    Multi.new()
    |> Multi.run(:result, fn _ ->
        params
        |> create_model()
        |> create_relations()
        |> case do
            result -> {:ok, result}
          end
      end)
    |> Repo.transaction()
    |> case do
        {:ok, result} -> {:ok, result.result}
        _ -> {:error, "创建失败"}
      end
  end

  defp atom(str), do: String.to_atom(str)
  defp str_to_model(str), do: Module.concat(Building, Macro.camelize(str))

  def create_model(params = %{"model" => model_str, "id" => id}) do
    model = str_to_model(model_str)
    view = str_to_model("#{model_str}_view")

    record = Repo.get!(model, id)
    record = view.render("#{model_str}.json", %{atom(model_str) => record})
    {record, params}
  end


  def create_model(params = %{"model" => model_str, "param" => param}) do
    model = str_to_model(model_str)
    view = str_to_model("#{model_str}_view")

    record =
      struct(model)
      |> model.changeset(param)
      |> Repo.insert!()

    record = view.render("#{model_str}.json", %{atom(model_str) => record})

    {record, params}
  end

  def create_relations({record, params = %{"model" => model}}) do
    params
    |> Map.get("relations", [])
    |> Enum.map(fn
        %{"to_model" => to_model_str, "to_ids" => to_ids} ->
          relation_model = str_to_model("#{model}_to_#{to_model_str}")
          to_model = str_to_model(to_model_str)
          view = str_to_model("#{to_model_str}_view")

          to_ids
          |> Enum.map(&%{atom("#{model}_id") => record.id, atom("#{to_model_str}_id") => &1})
          |> Enum.map(&struct(relation_model, &1))
          |> Enum.map(&Repo.insert!/1)

          tos =
            to_ids
            |> Enum.map(&Repo.get!(to_model, &1))
            |> Enum.map(&view.render("#{to_model_str}.json", %{atom(to_model_str) => &1}))

          {"#{to_model_str}s", tos}

        %{"to_model" => to_model_str, "to_params" => to_params} ->
          relation_model = str_to_model("#{model}_to_#{to_model_str}")
          to_model = str_to_model(to_model_str)
          view = str_to_model("#{to_model_str}_view")

          tos =
            to_params
            |> Enum.map(&to_model.changeset(struct(to_model), &1))
            |> Enum.map(&Repo.insert!/1)
            |> Enum.map(&view.render("#{to_model_str}.json", %{atom(to_model_str) => &1}))

          tos
          |> Enum.map(&%{atom("#{model}_id") => record.id, atom("#{to_model_str}_id") => &1.id})
          |> Enum.map(&struct(relation_model, &1))
          |> Enum.map(&Repo.insert!/1)

          {"#{to_model_str}s", tos}

        %{"from_model" => from_model_str, "from_ids" => from_ids} ->
          relation_model = str_to_model("#{from_model_str}_to_#{model}")
          from_model = str_to_model(from_model_str)
          view = str_to_model("#{from_model_str}_view")

          from_ids
          |> Enum.map(&%{atom("#{model}_id") => record.id, atom("#{from_model_str}_id") => &1})
          |> Enum.map(&struct(relation_model, &1))
          |> Enum.map(&Repo.insert!/1)

          froms =
            from_ids
            |> Enum.map(&Repo.get!(from_model, &1))
            |> Enum.map(&view.render("#{from_model_str}.json", %{atom(from_model_str) => &1}))

          {"#{from_model_str}s", froms}

        %{"from_model" => from_model_str, "from_params" => from_params} ->
          relation_model = str_to_model("#{model}_to_#{from_model_str}")
          from_model = str_to_model(from_model_str)
          view = str_to_model("#{from_model_str}_view")

          froms =
            from_params
            |> Enum.map(&from_model.changeset(struct(from_model), &1))
            |> Enum.map(&Repo.insert!/1)
            |> Enum.map(&view.render("#{from_model_str}.json", %{atom(from_model_str) => &1}))

          froms
          |> Enum.map(&%{atom("#{model}_id") => record.id, atom("#{from_model}_id") => &1.id})
          |> Enum.map(&struct(relation_model, &1))
          |> Enum.map(&Repo.insert!/1)

        {"#{from_model_str}s", froms}
      end)
    |> case do
        result -> Enum.into(result, record)
      end
  end

  def delete(%{"model" => model_str, "id" => id}) do
    model = str_to_model(model_str)
    view = str_to_model("#{model_str}_view")

    {:ok, record} =
      Repo.get!(model, id)
      |> Repo.delete()

    data = view.render("#{model_str}.json", %{atom(model_str) => record})

    {:ok, data}
  end

  def delete(%{"to_model" => to_model_str, "from_model" => from_model_str, "to_id" => to_id, "from_id" => from_id}) do
    relation_model = str_to_model("#{from_model_str}_to_#{to_model_str}")
    to_id_key = atom("#{to_model_str}_id")
    from_id_key = atom("#{from_model_str}_id")
    Repo.get_by!(relation_model, [{to_id_key, to_id}, {from_id_key, from_id}])
    |> Repo.delete()

    {:ok, %{status: "success"}}
  end

  def update(req = %{"model" => model_str, "param" => param, "id" => id}) do
    model = str_to_model(model_str)
    view = str_to_model("#{model_str}_view")
    relations = Map.get(req, "relations", [])

    Multi.new()
    |> Multi.run(:result, fn _ ->
        record = Repo.get!(model, id)

        param =
          if Map.get(req, "keep_history", false) do
            history =
              view.render("#{model_str}.json", %{atom(model_str) => record})
              |> Map.pop(:history, [])
              |> Tuple.to_list()
              |> Enum.reverse()
              |> List.flatten()

            Map.put(param, "history", history)
          else
            param
          end
        IO.inspect param

        record
        |> model.changeset(param)
        |> Repo.update()
        |> case do
            {:ok, record} ->
              record = view.render("#{model_str}.json", %{atom(model_str) => record})

              IO.inspect(relations)
              IO.inspect(record)
              IO.inspect(model_str)
              relations
              |> Enum.map(&update_relation(record, model_str, &1))
              |> Enum.into(record)
              |> case do
                  record -> {:ok, record}
                end

            {:error, reason} -> {:error, reason}
          end
        end)
    |> Repo.transaction()
    |> case do
        {:ok, result} -> {:ok, result.result}
        _ -> {:error, "更新失败"}
      end
  end

  defp update_relation(%{:id => from_id}, from_model_str, %{"action" => "replace", "to_model" => to_model_str, "to_id" => to_id}) do
    relation_model = str_to_model("#{from_model_str}_to_#{to_model_str}")

    where = [{atom("#{from_model_str}_id"), from_id}]
    query = (from m in relation_model, where: ^where)
    Repo.delete_all(query)

    create_param = %{
      "model" => from_model_str,
      "id" => from_id,
      "relations" => [%{"to_model" => to_model_str, "to_ids" => [to_id]}]
    }

    {:ok, result} = create(create_param)
    tos = Map.fetch!(result, "#{to_model_str}s")

    {"#{to_model_str}s", tos}
  end

  defp update_relation(%{:id => from_id}, from_model_str, %{"action" => "replace", "to_model" => to_model_str, "to_param" => to_param}) do
    relation_model = str_to_model("#{from_model_str}_to_#{to_model_str}")

    where = [{atom("#{from_model_str}_id"), from_id}]
    query = (from m in relation_model, where: ^where)
    Repo.delete_all(query)

    create_param = %{
      "model" => from_model_str,
      "id" => from_id,
      "relations" => [%{"to_model" => to_model_str, "to_params" => [to_param]}]
    }

    {:ok, result} = create(create_param)
    tos = Map.fetch!(result, "#{to_model_str}s")

    {"#{to_model_str}s", tos}
  end

  def query(%{"model" => model_str, "id" => id, "relations" => relations}) do
    model = str_to_model(model_str)

    preloads =
      relations
      |> Enum.map(&atom("#{&1}s"))

    record =
      (from m in model, preload: ^preloads, select: m)
      |> Repo.get!(id)

    view = str_to_model("#{model_str}_view")
    obj = view.render("#{model_str}.json", %{atom(model_str) => record})

    result =
      relations
      |> Enum.map(fn relation ->
          view = str_to_model("#{relation}_view")
          %{data: data} = view.render("index.json", record)
          {atom("#{relation}s"), data}
        end)
      |> Enum.into(obj)

    {:ok, result}
  end

  def query(%{"model" => model_str, "page" => page, "count" => count, "relations" => relations}) do
    limit = count
    offset = (page - 1) * count

    model = str_to_model(model_str)

    preloads =
      relations
      |> Enum.map(&atom("#{&1}s"))

    records =
    (from m in model, limit: ^limit, offset: ^offset, preload: ^preloads, select: m)
    |> Repo.all()

    total =
    (from m in model, select: count(m.id))
    |> Repo.one()
    IO.inspect total

    result =
      records
      |> Enum.map(fn record ->
      view = str_to_model("#{model_str}_view")
      obj = view.render("#{model_str}.json", %{atom(model_str) => record})

      relations
      |> Enum.map(fn relation ->
        view = str_to_model("#{relation}_view")
        %{data: data} = view.render("index.json", record)
        {atom("#{relation}s"), data}
      end)
      |> Enum.into(obj)
    end)

    info = %{"page" => page, "count" => length(result), "total" => total}
    {:ok, result, info}
  end

  def query(%{"model" => model_str, "relations" => relations}) do
    query(%{"model" => model_str, "page" => 1, "count" => 20, "relations" => relations})
  end
end
