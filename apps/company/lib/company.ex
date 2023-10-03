defmodule Company do
  use GenServer
  @moduledoc """
  Documentation for `Company`.
  a Genserver whose job is to hold the company information only.

  contains a struct at %Company{}
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    {:ok,
      %{
      cra_quebec_account: %{
        cra_account1: %{
          description: "FULL RATE",
          ei_rate: 1.4,
          number: ""
        },
        cra_account2: %{description: "", ei_rate: "", number: ""},
        cra_account3: %{description: "", ei_rate: "", number: ""},
        que_account: ""
      },
      dates: %{
        company_anniversary: "01/01",
        holiday_anniversary: "01/01",
        sick_anniversary: "01/01",
        vacation_anniversary: "01/01"
      },
      info: %{
        address1: "",
        address2: "",
        city: "",
        email: "",
        name: "",
        phone: "",
        postalcode: "",
        province: ""
      },
      settings: %{
        allow_arrears: 0,
        distribution: "",
        max_net_cheque: "0.00",
        pay_rate_search: "Company Default",
        payroll_frequency: "BI-WEEKLY26",
        payroll_level_message: "",
        use_global_settings: 0
      }

      }
    }
  end

  def update(section, key, val), do: GenServer.cast(__MODULE__, {:update, section, key, val})
  def handle_cast({:update, section, key, val}, state) do
    update = put_in(state, [section, key], val)
    :dets.insert(:company, {:company, update})
    {:noreply, update}
  end
 
  def update_all() do
    info = %{
      cra_quebec_account: %{
        cra_account1: %{
          description: "FULL RATE",
          ei_rate: 1.4,
          number: "82653 2053 RT0001"
        },
        cra_account2: %{description: "", ei_rate: "", number: ""},
        cra_account3: %{description: "", ei_rate: "", number: ""},
        que_account: ""
      },
      dates: %{
        company_anniversary: "01/01",
        holiday_anniversary: "01/01",
        sick_anniversary: "01/01",
        vacation_anniversary: "01/01"
      },
      info: %{
        address1: "",
        address2: "",
        city: "",
        email: "",
        name: "",
        phone: "",
        postalcode: "",
        province: ""
      },
      settings: %{
        allow_arrears: 0,
        distribution: "",
        max_net_cheque: "0.00",
        pay_rate_search: "Company Default",
        payroll_frequency: "BI-WEEKLY26",
        payroll_level_message: "",
        use_global_settings: 0
      }
      }
    GenServer.cast(__MODULE__, {:update_all, info})
  end
  @impl true
  def handle_cast({:update_all, info}, state) do
    :dets.insert(:company, {:company, info})
    {:noreply, info}
  end

  @doc """
  getstate
  """
  def info, do: GenServer.call(__MODULE__, {:getstate})
  def handle_call({:getstate}, _from, state), do: {:reply, state, state}

  @doc """
  Hello world.

  ## Examples

      iex> Company.hello()
      :world

  """
  def hello do
    :world
  end
end
