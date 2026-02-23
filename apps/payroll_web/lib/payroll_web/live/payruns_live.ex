defmodule PayrollWeb.PayrunsLive do
  use PayrollWeb, :live_view

  alias Core

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:runs, Core.list_payruns())
     |> assign(:filter, "")}
  end

  @impl true
  def handle_event("filter", %{"filter" => value}, socket) do
    {:noreply, assign(socket, :filter, to_string(value))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :runs, Core.list_payruns())}
  end

  @impl true
  def render(assigns) do
    visible_runs = visible_runs(assigns.runs, assigns.filter)
    assigns = assign(assigns, :visible_runs, visible_runs)

    ~H"""
    <div class="p-6 max-w-5xl mx-auto space-y-4">
      <div class="flex items-center justify-between gap-3">
        <div>
          <h1 class="text-xl font-bold">Payrun History</h1>
          <p class="text-sm text-gray-600">Finalized payroll runs</p>
        </div>

        <div class="flex items-center gap-2">
          <a href="/payrun" class="px-3 py-2 rounded border text-sm">Current Payrun</a>
          <a href="/app" class="text-sm underline">Back</a>
        </div>
      </div>

      <div class="rounded border p-4">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
          <form phx-change="filter" class="w-full sm:w-80">
            <label class="block text-xs text-gray-600">Filter (run id or date)</label>
            <input
              type="text"
              name="filter"
              value={@filter}
              placeholder="e.g. 2026-02 or PR-..."
              class="mt-1 w-full border rounded px-2 py-2 bg-white text-black"
            />
          </form>

          <button type="button" phx-click="refresh" class="px-3 py-2 rounded bg-black text-white">
            Refresh
          </button>
        </div>
      </div>

      <div class="rounded border p-4">
        <%= if @visible_runs == [] do %>
          <p class="text-sm text-gray-600">No finalized payruns yet.</p>
        <% else %>
          <div class="space-y-3">
            <%= for run <- @visible_runs do %>
              <div class="rounded border p-3">
                <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                  <div>
                    <div class="font-medium">
                      <a href={"/payruns/#{run.run_id}"} class="underline">
                        <%= run.run_id %>
                      </a>
                    </div>

                    <div class="text-sm text-gray-600">
                      <%= run.period_start %> – <%= run.period_end %>
                    </div>

                    <div class="text-xs text-gray-500 mt-1">
                      Saved: <%= run.inserted_at || "n/a" %>
                    </div>
                  </div>

                  <div class="grid grid-cols-3 gap-4 text-sm">
                    <div class="text-right">
                      <div class="text-xs text-gray-500">Employees</div>
                      <div class="font-semibold"><%= run.employee_count %></div>
                    </div>

                    <div class="text-right">
                      <div class="text-xs text-gray-500">Hours</div>
                      <div class="font-semibold"><%= fmt2(run.total_hours) %></div>
                    </div>

                    <div class="text-right">
                      <div class="text-xs text-gray-500">Gross</div>
                      <div class="font-semibold">$<%= fmt2(run.total_gross) %></div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp visible_runs(runs, ""), do: runs

  defp visible_runs(runs, filter) do
    needle = filter |> to_string() |> String.trim() |> String.downcase()

    if needle == "" do
      runs
    else
      Enum.filter(runs, fn run ->
        hay =
          [
            run.run_id,
            to_string(run.period_start),
            to_string(run.period_end),
            to_string(run.inserted_at)
          ]
          |> Enum.join(" ")
          |> String.downcase()

        String.contains?(hay, needle)
      end)
    end
  end

  defp fmt2(n) when is_integer(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp fmt2(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)

  defp fmt2(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> :erlang.float_to_binary(f, decimals: 2)
      _ -> "0.00"
    end
  end
end
