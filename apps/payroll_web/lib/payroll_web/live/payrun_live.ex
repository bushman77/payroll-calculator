defmodule PayrollWeb.PayrunLive do
  use PayrollWeb, :live_view

  alias Core
  alias Core.Payrun

  @impl true
  def mount(_params, _session, socket) do
    payrun = Payrun.build_current()

    {:ok,
     socket
     |> assign(:errors, %{})
     |> assign(:employee_filter, "")
     |> assign(:expanded, %{})
     |> assign(:last_saved_run_id, nil)
     |> assign_payrun(payrun)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    payrun = Payrun.build_for_date(socket.assigns.period_date)

    {:noreply,
     socket
     |> assign(:errors, %{})
     |> assign_payrun(payrun)}
  end

  @impl true
  def handle_event("prev_period", _params, socket) do
    prev_date = Date.add(socket.assigns.period.start_date, -1)
    payrun = Payrun.build_for_date(prev_date)

    {:noreply,
     socket
     |> assign(:errors, %{})
     |> assign_payrun(payrun)}
  end

  @impl true
  def handle_event("next_period", _params, socket) do
    next_date = Date.add(socket.assigns.period.end_date, 1)
    payrun = Payrun.build_for_date(next_date)

    {:noreply,
     socket
     |> assign(:errors, %{})
     |> assign_payrun(payrun)}
  end

  @impl true
  def handle_event("pick_date", %{"date" => date_iso}, socket) do
    case Date.from_iso8601(to_string(date_iso)) do
      {:ok, date} ->
        payrun = Payrun.build_for_date(date)

        {:noreply,
         socket
         |> assign(:errors, %{})
         |> assign_payrun(payrun)}

      _ ->
        {:noreply, assign(socket, :errors, %{date: "Invalid date (expected YYYY-MM-DD)"})}
    end
  end

  @impl true
  def handle_event("filter_employee", %{"employee_filter" => value}, socket) do
    {:noreply, assign(socket, :employee_filter, to_string(value))}
  end

  @impl true
  def handle_event("toggle_line", %{"name" => full_name}, socket) do
    expanded =
      Map.update(socket.assigns.expanded, full_name, true, fn v -> not v end)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  @impl true
  def handle_event("coming_soon", %{"feature" => feature}, socket) do
    {:noreply, put_flash(socket, :info, "#{feature} is next on the payrun roadmap")}
  end

@impl true
def handle_event("finalize", _params, socket) do
  lines = socket.assigns.lines || []

  if lines == [] do
    {:noreply, put_flash(socket, :error, "Cannot finalize an empty payrun")}
  else
    case Core.finalize_payrun(socket.assigns.payrun) do
      {:ok, saved_run} ->
        case extract_run_id(saved_run) do
          {:ok, run_id} ->
            {:noreply,
             socket
             |> assign(:last_saved_run_id, run_id)
             |> put_flash(:info, "Payrun finalized")
             |> push_navigate(to: "/payruns/#{run_id}")}

          :error ->
            {:noreply,
             put_flash(socket, :error, "Could not finalize payrun: invalid save response")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not finalize payrun: #{inspect(reason)}")}

      other ->
        case extract_run_id(other) do
          {:ok, run_id} ->
            {:noreply,
             socket
             |> assign(:last_saved_run_id, run_id)
             |> put_flash(:info, "Payrun finalized")
             |> push_navigate(to: "/payruns/#{run_id}")}

          :error ->
            {:noreply,
             put_flash(socket, :error, "Could not finalize payrun: #{inspect(other)}")}
        end
    end
  end
end

defp extract_run_id(run_id) when is_binary(run_id), do: {:ok, run_id}

defp extract_run_id(%{} = saved_run) do
  run_id =
    Map.get(saved_run, :run_id) ||
      Map.get(saved_run, "run_id") ||
      Map.get(saved_run, :id) ||
      Map.get(saved_run, "id")

  if is_binary(run_id), do: {:ok, run_id}, else: :error
end

defp extract_run_id(_), do: :error

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :visible_lines, visible_lines(assigns.lines, assigns.employee_filter))

    ~H"""
    <div class="p-6 max-w-5xl mx-auto space-y-4">
      <div class="flex items-center justify-between gap-3">
        <div>
          <h1 class="text-xl font-bold">Payrun</h1>
          <p class="text-sm text-gray-600">Period payroll totals from saved hours entries</p>
        </div>

        <a href="/app" class="text-sm underline">Back</a>
    <a href="/payruns" class="px-3 py-2 rounded border text-sm">History</a>
      </div>

      <div class="rounded border p-4 space-y-3">
        <div class="flex flex-col sm:flex-row sm:items-end gap-3 sm:justify-between">
          <div>
            <div class="text-sm font-semibold">Pay period</div>
            <div class="text-sm text-gray-700">
              <%= format_date(@period.start_date) %> – <%= format_date(@period.end_date) %>
            </div>
            <%= if Map.get(@period, :label) do %>
              <div class="text-xs text-gray-500 mt-1"><%= @period.label %></div>
            <% end %>
          </div>

          <div class="flex flex-wrap items-end gap-2">
            <button type="button" phx-click="prev_period" class="px-3 py-2 border rounded bg-white">
              ← Prev
            </button>

            <form phx-change="pick_date" class="flex flex-col">
              <label class="text-xs text-gray-600">Jump by date</label>
              <input
                type="date"
                name="date"
                value={Date.to_iso8601(@period_date)}
                class="border rounded px-2 py-1 bg-white text-black"
              />
            </form>

            <button type="button" phx-click="next_period" class="px-3 py-2 border rounded bg-white">
              Next →
            </button>

            <button type="button" phx-click="refresh" class="px-3 py-2 rounded bg-black text-white">
              Refresh
            </button>
          </div>
        </div>

        <%= if msg = @errors[:date] do %>
          <p class="text-sm text-red-600"><%= msg %></p>
        <% end %>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div class="rounded border p-4">
          <div class="text-xs text-gray-600">Employees</div>
          <div class="text-2xl font-bold"><%= @employee_count %></div>
        </div>

        <div class="rounded border p-4">
          <div class="text-xs text-gray-600">Total hours</div>
          <div class="text-2xl font-bold"><%= fmt2(@total_hours) %></div>
        </div>

        <div class="rounded border p-4">
          <div class="text-xs text-gray-600">Total gross</div>
          <div class="text-2xl font-bold">$<%= fmt2(@total_gross) %></div>
        </div>
      </div>

      <div class="rounded border p-4 space-y-3">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
          <div>
            <h2 class="text-sm font-semibold">Run actions</h2>
            <p class="text-xs text-gray-500">Scaffold buttons for paystubs / ROE flow</p>
            <%= if @last_saved_run_id do %>
              <p class="text-xs text-green-700 mt-1">
                Last saved payrun: <span class="font-mono"><%= @last_saved_run_id %></span>
              </p>
            <% end %>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              phx-click="coming_soon"
              phx-value-feature="Generate paystubs"
              class="px-3 py-2 rounded border bg-white"
            >
              Paystubs
            </button>

            <button
              type="button"
              phx-click="coming_soon"
              phx-value-feature="ROE export"
              class="px-3 py-2 rounded border bg-white"
            >
              ROE
            </button>

    <button
    type="button"
    phx-click="finalize"
    class="px-3 py-2 rounded bg-black text-white disabled:opacity-50"
    disabled={@lines == []}
    >
    Finalize
    </button>

          </div>
        </div>
      </div>

      <div class="rounded border p-4">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
          <div>
            <h2 class="text-sm font-semibold">Employee totals</h2>
            <div class="text-xs text-gray-500 mt-1">
              <%= length(@visible_lines) %> visible · <%= length(@lines) %> total
            </div>
          </div>

          <form phx-change="filter_employee" class="w-full sm:w-72">
            <label class="block text-xs text-gray-600">Filter employee</label>
            <input
              type="text"
              name="employee_filter"
              value={@employee_filter}
              placeholder="Type a name..."
              class="mt-1 w-full border rounded px-2 py-2 bg-white text-black"
            />
          </form>
        </div>

        <div class="mt-3 space-y-3">
          <%= if @visible_lines == [] do %>
            <p class="text-sm text-gray-600">No hours found for this pay period.</p>
          <% else %>
            <%= for line <- @visible_lines do %>
              <% expanded? = Map.get(@expanded, line.full_name, false) %>

              <div class="rounded border p-3">
                <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                  <div>
                    <div class="font-medium"><%= line.full_name %></div>
                    <div class="text-sm text-gray-600">
                      <%= fmt2(line.total_hours) %>h · $<%= fmt2(line.hourly_rate) %>/hr
                    </div>
                  </div>

                  <div class="flex items-center gap-3">
                    <div class="text-right">
                      <div class="text-xs text-gray-500">Gross</div>
                      <div class="font-semibold">$<%= fmt2(line.gross) %></div>
                    </div>

                    <button
                      type="button"
                      phx-click="toggle_line"
                      phx-value-name={line.full_name}
                      class="px-3 py-2 border rounded text-sm"
                    >
                      <%= if expanded?, do: "Hide", else: "Details" %>
                    </button>
                  </div>
                </div>

                <%= if expanded? and line.entries != [] do %>
                  <div class="mt-3 overflow-x-auto">
                    <table class="w-full text-sm">
                      <thead>
                        <tr class="text-left text-gray-600 border-b">
                          <th class="py-1 pr-2">Date</th>
                          <th class="py-1 pr-2">Shift</th>
                          <th class="py-1 pr-2">Hours</th>
                          <th class="py-1 pr-2">Rate</th>
                          <th class="py-1 pr-2">Gross</th>
                          <th class="py-1">Notes</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for e <- line.entries do %>
                          <tr class="border-b last:border-b-0">
                            <td class="py-1 pr-2 whitespace-nowrap"><%= e.date %></td>
                            <td class="py-1 pr-2 whitespace-nowrap"><%= e.shift_start %> – <%= e.shift_end %></td>
                            <td class="py-1 pr-2 whitespace-nowrap"><%= fmt2(e.hours) %></td>
                            <td class="py-1 pr-2 whitespace-nowrap">$<%= fmt2(e.rate) %></td>
                            <td class="py-1 pr-2 whitespace-nowrap">$<%= fmt2(e.gross) %></td>
                            <td class="py-1"><%= e.notes %></td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------- helpers ----------------

  defp assign_payrun(socket, payrun) do
    socket
    |> assign(:payrun, payrun)
    |> assign(:period, payrun.period)
    |> assign(:period_date, payrun.period.start_date)
    |> assign(:employee_count, payrun.employee_count)
    |> assign(:total_hours, payrun.total_hours)
    |> assign(:total_gross, payrun.total_gross)
    |> assign(:lines, payrun.lines)
    |> prune_expanded(payrun.lines)
  end

  defp prune_expanded(socket, lines) do
    valid_names = MapSet.new(Enum.map(lines, & &1.full_name))

    expanded =
      (socket.assigns[:expanded] || %{})
      |> Enum.filter(fn {name, _} -> MapSet.member?(valid_names, name) end)
      |> Map.new()

    assign(socket, :expanded, expanded)
  end

  defp visible_lines(lines, ""), do: lines

  defp visible_lines(lines, filter) do
    needle = filter |> to_string() |> String.trim() |> String.downcase()

    if needle == "" do
      lines
    else
      Enum.filter(lines, fn line ->
        String.contains?(String.downcase(to_string(line.full_name)), needle)
      end)
    end
  end

  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_date(other), do: to_string(other)

  defp fmt2(n) when is_integer(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp fmt2(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)

  defp fmt2(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> :erlang.float_to_binary(f, decimals: 2)
      _ -> "0.00"
    end
  end
end
