defmodule Employee do
  @moduledoc """
  Employee domain functions (library module).

  Storage (Mnesia via Database app):
    {Employee, full_name :: String.t(), employee_struct :: %Employee{}}

  v1 key: full_name (string)
  """

  defstruct Core.struct(Employee)

  @type t :: %__MODULE__{}

  # ----------------------------
  # Read
  # ----------------------------
  @spec all() :: [{String.t(), t()}]
  def all do
    Database.match({Employee, :_, :_})
    |> Enum.map(fn {Employee, full_name, emp} -> {full_name, normalize(emp)} end)
    |> Enum.sort_by(fn {full_name, _} -> String.downcase(full_name) end)
  end

  @spec active() :: [{String.t(), t()}]
  def active do
    all()
    |> Enum.filter(fn {_name, emp} -> Map.get(emp, :status, :active) == :active end)
  end

  @spec get(String.t()) :: {:ok, t()} | {:error, :not_found}
  def get(full_name) when is_binary(full_name) do
    case Database.match({Employee, full_name, :_}) do
      [{Employee, ^full_name, emp}] -> {:ok, normalize(emp)}
      [] -> {:error, :not_found}
    end
  end

  # ----------------------------
  # Create
  # ----------------------------
  @spec create(String.t(), String.t(), number()) :: {:ok, String.t()} | {:error, term()}
  def create(givenname, surname, hourly_rate \\ 0.0)
      when is_binary(givenname) and is_binary(surname) and is_number(hourly_rate) do
    givenname = String.trim(givenname)
    surname = String.trim(surname)

    cond do
      givenname == "" or surname == "" ->
        {:error, :name_required}

      hourly_rate < 0 ->
        {:error, :invalid_rate}

      true ->
        full_name = full_name(givenname, surname)

        emp =
          struct(%__MODULE__{}, %{
            givenname: givenname,
            surname: surname,
            hourly_rate: hourly_rate * 1.0,
            status: :active
          })

        Database.insert({Employee, full_name, emp})
        {:ok, full_name}
    end
  end

  # ----------------------------
  # Update
  # ----------------------------
  @spec set_rate(String.t(), number()) :: {:ok, t()} | {:error, term()}
  def set_rate(full_name, hourly_rate) when is_binary(full_name) and is_number(hourly_rate) do
    cond do
      hourly_rate < 0 ->
        {:error, :invalid_rate}

      true ->
        with {:ok, emp} <- get(full_name) do
          updated = Map.put(emp, :hourly_rate, hourly_rate * 1.0)
          Database.insert({Employee, full_name, updated})
          {:ok, updated}
        end
    end
  end

  @spec deactivate(String.t()) :: {:ok, t()} | {:error, term()}
  def deactivate(full_name) when is_binary(full_name) do
    with {:ok, emp} <- get(full_name) do
      updated = Map.put(emp, :status, :inactive)
      Database.insert({Employee, full_name, updated})
      {:ok, updated}
    end
  end

  @spec activate(String.t()) :: {:ok, t()} | {:error, term()}
  def activate(full_name) when is_binary(full_name) do
    with {:ok, emp} <- get(full_name) do
      updated = Map.put(emp, :status, :active)
      Database.insert({Employee, full_name, updated})
      {:ok, updated}
    end
  end

  # ----------------------------
  # Helpers
  # ----------------------------
  defp full_name(givenname, surname), do: givenname <> " " <> surname

  # Normalize any old stored value into %Employee{}
  defp normalize(%__MODULE__{} = emp), do: emp

  defp normalize(map) when is_map(map) do
    # If older records were stored as plain maps, coerce into struct
    struct(%__MODULE__{}, Map.merge(Map.from_struct(struct(%__MODULE__{})), map))
  end

  defp normalize(other), do: other
end
