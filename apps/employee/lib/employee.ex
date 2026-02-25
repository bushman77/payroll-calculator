defmodule Employee do
  @moduledoc """
  Employee domain functions (library module).

  Storage (Mnesia via Database app):
    {Employee, full_name :: String.t(), employee_struct :: %Employee{}}

  v1 key: full_name (string)
  """

  defstruct [
    :surname,
    :givenname,
    :hourly_rate,
    :status,
    :address1,
    :address2,
    :city,
    :province,
    :postalcode,
    :sin,
    :badge,
    :initial_hire_date,
    :last_termination,
    :treaty_number,
    :band_name,
    :employee_self_service,
    :number,
    :family_number,
    :reference_number,
    :birth_date,
    :sex,
    :home_phone,
    :alternate_phone,
    :email,
    :notes,
    :photo
  ]

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
    create(%{
      "givenname" => givenname,
      "surname" => surname,
      "hourly_rate" => hourly_rate
    })
  end

  @doc """
  Create an employee from a map (string keys are fine).
  Returns {:ok, full_name} or {:error, reason}.
  """
  @spec create(map()) :: {:ok, String.t()} | {:error, term()}
  def create(attrs) when is_map(attrs) do
    givenname = attrs |> fetch_string("givenname") |> String.trim()
    surname = attrs |> fetch_string("surname") |> String.trim()

    hourly_rate =
      case attrs["hourly_rate"] do
        n when is_number(n) -> n * 1.0
        s when is_binary(s) -> parse_float(s)
        _ -> 0.0
      end

    cond do
      givenname == "" or surname == "" ->
        {:error, :name_required}

      hourly_rate < 0 ->
        {:error, :invalid_rate}

      true ->
        full_name = full_name(givenname, surname)

        base =
          struct(%__MODULE__{}, %{
            givenname: givenname,
            surname: surname,
            hourly_rate: hourly_rate,
            status: :active,
            notes: [],
            photo: ""
          })

        updated = apply_attrs(base, attrs)

        Database.insert({Employee, full_name, updated})
        {:ok, full_name}
    end
  end

  # ----------------------------
  # Update
  # ----------------------------
  @spec update(String.t(), map()) :: {:ok, t()} | {:error, term()}
  def update(full_name, attrs) when is_binary(full_name) and is_map(attrs) do
    with {:ok, emp} <- get(full_name) do
      updated = apply_attrs(emp, attrs)
      Database.insert({Employee, full_name, updated})
      {:ok, updated}
    end
  end

  @spec set_rate(String.t(), number()) :: {:ok, t()} | {:error, term()}
  def set_rate(full_name, hourly_rate) when is_binary(full_name) and is_number(hourly_rate) do
    cond do
      hourly_rate < 0 -> {:error, :invalid_rate}
      true -> update(full_name, %{"hourly_rate" => hourly_rate})
    end
  end

  @spec deactivate(String.t()) :: {:ok, t()} | {:error, term()}
  def deactivate(full_name) when is_binary(full_name),
    do: update(full_name, %{"status" => :inactive})

  @spec activate(String.t()) :: {:ok, t()} | {:error, term()}
  def activate(full_name) when is_binary(full_name),
    do: update(full_name, %{"status" => :active})

  # ----------------------------
  # Helpers
  # ----------------------------
  defp full_name(givenname, surname), do: givenname <> " " <> surname

  defp normalize(%__MODULE__{} = emp), do: emp

  defp normalize(map) when is_map(map) do
    defaults =
      %__MODULE__{}
      |> Map.from_struct()

    struct(%__MODULE__{}, Map.merge(defaults, map))
  end

  defp normalize(other), do: other

  defp fetch_string(map, key) do
    case map[key] do
      nil -> ""
      v when is_binary(v) -> v
      v -> to_string(v)
    end
  end

  defp parse_float(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {n, _} -> n
      _ -> 0.0
    end
  end

  defp apply_attrs(%__MODULE__{} = emp, attrs) when is_map(attrs) do
    emp
    |> put_if_present(:address1, attrs, "address1")
    |> put_if_present(:address2, attrs, "address2")
    |> put_if_present(:city, attrs, "city")
    |> put_if_present(:province, attrs, "province")
    |> put_if_present(:postalcode, attrs, "postalcode")
    |> put_if_present(:home_phone, attrs, "home_phone")
    |> put_if_present(:alternate_phone, attrs, "alternate_phone")
    |> put_if_present(:email, attrs, "email")
    |> put_if_present(:sin, attrs, "sin")
    |> put_if_present(:badge, attrs, "badge")
    |> put_if_present(:initial_hire_date, attrs, "initial_hire_date")
    |> put_if_present(:last_termination, attrs, "last_termination")
    |> put_if_present(:treaty_number, attrs, "treaty_number")
    |> put_if_present(:band_name, attrs, "band_name")
    |> put_if_present(:employee_self_service, attrs, "employee_self_service")
    |> put_if_present(:number, attrs, "number")
    |> put_if_present(:family_number, attrs, "family_number")
    |> put_if_present(:reference_number, attrs, "reference_number")
    |> put_if_present(:birth_date, attrs, "birth_date")
    |> put_if_present(:sex, attrs, "sex")
    |> put_rate_if_present(attrs)
    |> put_status_if_present(attrs)
  end

  defp put_if_present(emp, field, attrs, key) do
    val =
      case attrs[key] do
        nil -> nil
        v when is_binary(v) -> String.trim(v)
        v -> to_string(v)
      end

    cond do
      is_nil(val) -> emp
      val == "" -> emp
      true -> Map.put(emp, field, val)
    end
  end

  defp put_rate_if_present(emp, attrs) do
    case attrs["hourly_rate"] do
      nil -> emp
      n when is_number(n) -> Map.put(emp, :hourly_rate, n * 1.0)
      s when is_binary(s) -> Map.put(emp, :hourly_rate, parse_float(s))
      _ -> emp
    end
  end

  defp put_status_if_present(emp, attrs) do
    case attrs["status"] do
      nil -> emp
      :active -> Map.put(emp, :status, :active)
      :inactive -> Map.put(emp, :status, :inactive)
      "active" -> Map.put(emp, :status, :active)
      "inactive" -> Map.put(emp, :status, :inactive)
      _ -> emp
    end
  end
end
