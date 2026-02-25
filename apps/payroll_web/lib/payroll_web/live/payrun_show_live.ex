defmodule PayrollWeb.PayrunShowLive do
  use PayrollWeb, :live_view

  alias Core

  @impl true
  def mount(%{"run_id" => run_id}, _session, socket) do
    case Core.get_payrun(run_id) do
      {:ok, run} ->
        {:ok, assign_run(socket, run)}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Payrun not found")
         |> push_navigate(to: "/payruns")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Could not load payrun")
         |> push_navigate(to: "/payruns")}
    end
  end

@impl true
def handle_event("download_paystub", %{"name" => full_name}, socket) do
  run_id =
    socket.assigns.run[:run_id] ||
      socket.assigns.run["run_id"]

  {:noreply,
   push_navigate(socket,
     to: "/payruns/#{run_id}/paystub/#{URI.encode(full_name)}"
   )}
end

  @impl true
  def handle_event("coming_soon", %{"feature" => feature}, socket) do
    {:noreply, put_flash(socket, :info, "#{feature} is next")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-5xl mx-auto space-y-4">
      <div class="flex items-center justify-between gap-3">
        <div>
          <h1 class="text-xl font-bold">Payrun <%= @run.run_id %></h1>
          <p class="text-sm text-gray-600">
            <%= @run.period_start %> – <%= @run.period_end %>
          </p>
        </div>

        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="coming_soon"
            phx-value-feature="Export payrun"
            class="px-3 py-2 rounded border"
          >
            Export
          </button>

          <a href="/payruns" class="text-sm underline">Back to history</a>
        </div>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div class="rounded border p-4">
          <div class="text-xs text-gray-600">Employees</div>
          <div class="text-2xl font-bold"><%= Map.get(@summary, :employee_count, 0) %></div>
        </div>

        <div class="rounded border p-4">
          <div class="text-xs text-gray-600">Total hours</div>
          <div class="text-2xl font-bold"><%= fmt2(Map.get(@summary, :total_hours, 0)) %></div>
        </div>

        <div class="rounded border p-4">
          <div class="text-xs text-gray-600">Total gross</div>
          <div class="text-2xl font-bold">$<%= fmt2(Map.get(@summary, :total_gross, 0)) %></div>
        </div>
      </div>

      <div class="rounded border p-4">
        <h2 class="text-sm font-semibold">Employee lines</h2>

        <div class="mt-3 space-y-3">
          <%= if @lines == [] do %>
            <p class="text-sm text-gray-600">No lines saved in this payrun.</p>
          <% else %>
            <%= for line <- @lines do %>
              <div class="rounded border p-3">
                <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                  <div>
                    <div class="font-medium"><%= line.full_name %></div>
                    <div class="text-sm text-gray-600">
                      <%= fmt2(line.total_hours) %>h · $<%= fmt2(line.hourly_rate) %>/hr
                    </div>
                  </div>

                  <div class="flex items-center gap-2">
                    <div class="text-right">
                      <div class="text-xs text-gray-500">Gross</div>
                      <div class="font-semibold">$<%= fmt2(line.gross) %></div>
                    </div>

                    <button
                      type="button"
                      phx-click="download_paystub"
                      phx-value-name={line.full_name}
                      class="px-3 py-2 rounded border bg-white text-sm"
                    >
                      Paystub PDF
                    </button>
                  </div>
                </div>

                <%= if Map.get(line, :entries, []) != [] do %>
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
                        <%= for e <- Map.get(line, :entries, []) do %>
                          <tr class="border-b last:border-b-0">
                            <td class="py-1 pr-2 whitespace-nowrap"><%= e.date %></td>
                            <td class="py-1 pr-2 whitespace-nowrap">
                              <%= e.shift_start %> – <%= e.shift_end %>
                            </td>
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

  defp assign_run(socket, run) do
    lines = Map.get(run, :lines, [])
    summary = Map.get(run, :summary, build_summary(lines))

    socket
    |> assign(:run, run)
    |> assign(:lines, lines)
    |> assign(:summary, summary)
  end

  defp build_summary(lines) do
    total_hours =
      Enum.reduce(lines, 0.0, fn line, acc -> acc + num(Map.get(line, :total_hours, 0)) end)

    total_gross =
      Enum.reduce(lines, 0.0, fn line, acc -> acc + num(Map.get(line, :gross, 0)) end)

    %{
      employee_count: length(lines),
      total_hours: total_hours,
      total_gross: total_gross
    }
  end

  defp num(n) when is_integer(n), do: n * 1.0
  defp num(n) when is_float(n), do: n

  defp num(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> f
      _ -> 0.0
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
