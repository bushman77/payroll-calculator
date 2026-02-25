defmodule Company do
  @moduledoc """
  Single-tenant Company settings + bootstrap.

  Ownership:
  - Company owns the domain/settings record.
  - Database owns all Mnesia operations and tables.
  """

  use GenServer

  @settings_key :singleton

  # Defaults for a new install
  @default_settings %{
    name: "Payroll Calculator",
    province: "BC",
    pay_frequency: :biweekly,
    anchor_payday: "2023-01-13",
    # current policy you’re using in Core.periods/2
    period_start_offset_days: -20,
    period_cutoff_offset_days: -7
  }

  # -----------------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------------
  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  # Current API
  def settings, do: GenServer.call(__MODULE__, :settings)

  def update_settings(attrs) when is_map(attrs),
    do: GenServer.call(__MODULE__, {:update_settings, attrs})

  # Compatibility API (for Core / older callers)
  def get_settings, do: settings()

  def put_settings(attrs) when is_map(attrs), do: update_settings(attrs)

  # -----------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------
  @impl true
  def init(:ok) do
    # Ensure the record exists (idempotent)
    settings = ensure_settings!()
    {:ok, settings}
  end

  @impl true
  def handle_call(:settings, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:update_settings, attrs}, _from, state) do
    with {:ok, updated} <- validate_settings(Map.merge(state, attrs)),
         :ok <- persist_settings(updated) do
      {:reply, {:ok, updated}, updated}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # -----------------------------------------------------------------------------
  # Internal helpers
  # -----------------------------------------------------------------------------
  defp ensure_settings! do
    case Database.match({CompanySettings, @settings_key, :_}) do
      [{CompanySettings, @settings_key, settings}] when is_map(settings) ->
        settings

      [] ->
        # first boot
        :ok = persist_settings(@default_settings)
        @default_settings
    end
  end

  defp persist_settings(settings) when is_map(settings) do
    Database.insert({CompanySettings, @settings_key, settings})
    :ok
  end

  defp validate_settings(%{} = settings) do
    with {:ok, name} <- validate_nonempty(settings.name, :name),
         {:ok, province} <- validate_nonempty(settings.province, :province),
         {:ok, pay_frequency} <- validate_pay_frequency(settings.pay_frequency),
         {:ok, anchor_payday} <- validate_iso_date(settings.anchor_payday, :anchor_payday),
         {:ok, start_off} <-
           validate_integer(settings.period_start_offset_days, :period_start_offset_days),
         {:ok, cutoff_off} <-
           validate_integer(settings.period_cutoff_offset_days, :period_cutoff_offset_days) do
      {:ok,
       %{
         settings
         | name: name,
           province: province,
           pay_frequency: pay_frequency,
           anchor_payday: anchor_payday,
           period_start_offset_days: start_off,
           period_cutoff_offset_days: cutoff_off
       }}
    end
  end

  defp validate_nonempty(val, field) when is_binary(val) do
    if String.trim(val) == "" do
      {:error, "#{field} cannot be empty"}
    else
      {:ok, val}
    end
  end

  defp validate_nonempty(_val, field), do: {:error, "#{field} must be a string"}

  defp validate_pay_frequency(:biweekly), do: {:ok, :biweekly}
  defp validate_pay_frequency(val), do: {:error, "unsupported pay_frequency: #{inspect(val)}"}

  defp validate_iso_date(val, field) when is_binary(val) do
    case Date.from_iso8601(val) do
      {:ok, _} -> {:ok, val}
      _ -> {:error, "#{field} must be YYYY-MM-DD"}
    end
  end

  defp validate_iso_date(_val, field), do: {:error, "#{field} must be YYYY-MM-DD"}

  defp validate_integer(val, _field) when is_integer(val), do: {:ok, val}
  defp validate_integer(_val, field), do: {:error, "#{field} must be an integer"}
end
