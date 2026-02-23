defmodule PayrollWeb.HoursLive do
  use PayrollWeb, :live_view

  alias PayrollWeb.HoursLive.AddEntrySection
  alias PayrollWeb.HoursLive.EmployeeSection
  alias PayrollWeb.HoursLive.Header
  alias PayrollWeb.HoursLive.RecentEntriesSection

  @minutes ~w(00 05 10 15 20 25 30 35 40 45 50 55)

  @impl true
  def mount(_params, _session, socket) do
    employees =
      Employee.active()
      |> Enum.map(fn {full_name, emp} -> {full_name, emp} end)

    selected =
      case employees do
        [{name, _} | _] -> name
        _ -> ""
      end

    form_params = default_params(selected)

    {shift_start, shift_end, hours} =
      derive_times_and_hours(
        form_params["start_hour"],
        form_params["start_min"],
        form_params["end_hour"],
        form_params["end_min"]
      )

    {:ok,
     socket
     |> assign(:minutes, @minutes)
     |> assign(:hours_options, hours_options())
     |> assign(:employees, employees)
     |> assign(:selected, selected)
     |> assign(:entries, load_entries(selected))
     |> assign(:summary, load_summary(selected))
     |> assign(:errors, %{})
     # controlled time assigns (source of truth for live updates)
     |> assign(:start_hour, form_params["start_hour"])
     |> assign(:start_min, form_params["start_min"])
     |> assign(:end_hour, form_params["end_hour"])
     |> assign(:end_min, form_params["end_min"])
     |> assign(:shift_start, shift_start)
     |> assign(:shift_end, shift_end)
     |> assign(:hours_text, hours)
     # form holds non-time inputs + hidden values for submit
     |> assign(:form, to_form(form_params, as: :h))}
  end

  @impl true
  def handle_event("select_employee", %{"employee" => full_name}, socket) do
    form_params = default_params(full_name)

    {shift_start, shift_end, hours} =
      derive_times_and_hours(
        form_params["start_hour"],
        form_params["start_min"],
        form_params["end_hour"],
        form_params["end_min"]
      )

    {:noreply,
     socket
     |> assign(:selected, full_name)
     |> assign(:entries, load_entries(full_name))
     |> assign(:summary, load_summary(full_name))
     |> assign(:errors, %{})
     |> assign(:start_hour, form_params["start_hour"])
     |> assign(:start_min, form_params["start_min"])
     |> assign(:end_hour, form_params["end_hour"])
     |> assign(:end_min, form_params["end_min"])
     |> assign(:shift_start, shift_start)
     |> assign(:shift_end, shift_end)
     |> assign(:hours_text, hours)
     |> assign(:form, to_form(form_params, as: :h))}
  end

  @impl true
  def handle_event("pick_time", %{"_target" => ["h", field]} = params, socket) do
    h =
      cond do
        is_map(params["h"]) ->
          params["h"]

        is_binary(params["value"]) ->
          Plug.Conn.Query.decode(params["value"])["h"] || %{}

        true ->
          %{}
      end

    value = pad2(Map.get(h, field, ""))

    socket =
      case field do
        "start_hour" -> assign(socket, :start_hour, value)
        "start_min" -> assign(socket, :start_min, value)
        "end_hour" -> assign(socket, :end_hour, value)
        "end_min" -> assign(socket, :end_min, value)
        _ -> socket
      end

    {shift_start, shift_end, hours} =
      derive_times_and_hours(
        socket.assigns.start_hour,
        socket.assigns.start_min,
        socket.assigns.end_hour,
        socket.assigns.end_min
      )

    {:noreply,
     socket
     |> assign(:shift_start, shift_start)
     |> assign(:shift_end, shift_end)
     |> assign(:hours_text, hours)
     |> refresh_form_hidden_times()}
  end

  @impl true
  def handle_event("validate", %{"h" => params}, socket) do
    merged = Map.merge(socket.assigns.form.params, params)

    {_, errors} = validate_params(merged, socket.assigns.selected, socket.assigns.hours_text)

    {:noreply,
     socket
     |> assign(:errors, errors)
     |> assign(:form, to_form(merged, as: :h))}
  end

  @impl true
  def handle_event("save", %{"h" => params}, socket) do
    merged = Map.merge(socket.assigns.form.params, params)

    {_, errors} = validate_params(merged, socket.assigns.selected, socket.assigns.hours_text)

    if map_size(errors) > 0 do
      {:noreply,
       socket
       |> assign(:errors, errors)
       |> assign(:form, to_form(merged, as: :h))}
    else
      payload = %{
        full_name: socket.assigns.selected,
        date: (merged["date"] || "") |> String.trim(),
        shift_start: socket.assigns.shift_start,
        shift_end: socket.assigns.shift_end,
        rate: parse_float!(merged["rate"]),
        hours: parse_float!(socket.assigns.hours_text),
        notes: (merged["notes"] || "") |> to_string()
      }

      case Core.add_hours_entry(payload) do
        :ok ->
          reset_after_save(socket)

        {:ok, _} ->
          reset_after_save(socket)

        {:error, {:duplicate_hours_entry, _meta}} ->
          {:noreply,
           socket
           |> assign(:errors, Map.put(socket.assigns.errors, :shift_time, "duplicate entry for this exact shift"))
           |> assign(:form, to_form(merged, as: :h))}

        {:error, {:overlap_hours_entry, _meta}} ->
          {:noreply,
           socket
           |> assign(:errors, Map.put(socket.assigns.errors, :shift_time, "shift overlaps an existing entry on this date"))
           |> assign(:form, to_form(merged, as: :h))}

        # Backward-compatible patterns while refactor settles
        {:error, :duplicate} ->
          {:noreply,
           socket
           |> assign(:errors, Map.put(socket.assigns.errors, :shift_time, "duplicate entry for this exact shift"))
           |> assign(:form, to_form(merged, as: :h))}

        {:error, :overlap} ->
          {:noreply,
           socket
           |> assign(:errors, Map.put(socket.assigns.errors, :shift_time, "shift overlaps an existing entry on this date"))
           |> assign(:form, to_form(merged, as: :h))}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not save entry: #{inspect(reason)}")
           |> assign(:form, to_form(merged, as: :h))}

        other ->
          {:noreply,
           socket
           |> put_flash(:error, "Unexpected save result: #{inspect(other)}")
           |> assign(:form, to_form(merged, as: :h))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-xl mx-auto space-y-4">
      <Header.render title="Hours" subtitle="Times auto-calc hours (hours is read-only)." back_href="/app" />

      <EmployeeSection.render employees={@employees} selected={@selected} summary={@summary} />

      <%= if @selected != "" do %>
        <AddEntrySection.render
          form={@form}
          errors={@errors}
          minutes={@minutes}
          hours_options={@hours_options}
          start_hour={@start_hour}
          start_min={@start_min}
          end_hour={@end_hour}
          end_min={@end_min}
          shift_start={@shift_start}
          shift_end={@shift_end}
          hours_text={@hours_text}
        />

        <RecentEntriesSection.render entries={@entries} />
      <% end %>
    </div>
    """
  end

  # ---------------- helpers ----------------

  defp reset_after_save(socket) do
    full_name = socket.assigns.selected
    fresh = default_params(full_name)

    {shift_start, shift_end, hours} =
      derive_times_and_hours(
        fresh["start_hour"],
        fresh["start_min"],
        fresh["end_hour"],
        fresh["end_min"]
      )

    {:noreply,
     socket
     |> put_flash(:info, "Hours saved")
     |> assign(:entries, load_entries(full_name))
     |> assign(:summary, load_summary(full_name))
     |> assign(:errors, %{})
     |> assign(:start_hour, fresh["start_hour"])
     |> assign(:start_min, fresh["start_min"])
     |> assign(:end_hour, fresh["end_hour"])
     |> assign(:end_min, fresh["end_min"])
     |> assign(:shift_start, shift_start)
     |> assign(:shift_end, shift_end)
     |> assign(:hours_text, hours)
     |> assign(:form, to_form(fresh, as: :h))}
  end

  defp refresh_form_hidden_times(socket) do
    merged =
      socket.assigns.form.params
      |> Map.put("start_hour", socket.assigns.start_hour)
      |> Map.put("start_min", socket.assigns.start_min)
      |> Map.put("end_hour", socket.assigns.end_hour)
      |> Map.put("end_min", socket.assigns.end_min)
      |> Map.put("shift_start", socket.assigns.shift_start)
      |> Map.put("shift_end", socket.assigns.shift_end)
      |> Map.put("hours", socket.assigns.hours_text)

    assign(socket, :form, to_form(merged, as: :h))
  end

  defp derive_times_and_hours(sh, sm, eh, em) do
    sh = pad2(sh || "07")
    sm = pad2(sm || "00")
    eh = pad2(eh || "15")
    em = pad2(em || "00")

    shift_start = "#{sh}:#{sm}"
    shift_end = "#{eh}:#{em}"

    hours =
      case minutes_between(shift_start, shift_end) do
        {:ok, mins} when mins > 0 -> :erlang.float_to_binary(mins / 60.0, decimals: 2)
        _ -> ""
      end

    {shift_start, shift_end, hours}
  end

  defp hours_options, do: for(h <- 0..23, do: String.pad_leading("#{h}", 2, "0"))

  defp default_params(full_name) do
    rate =
      case Employee.get(full_name) do
        {:ok, emp} -> Map.get(emp, :hourly_rate, 0.0)
        _ -> 0.0
      end

    %{
      "full_name" => full_name,
      "date" => Date.utc_today() |> Date.to_iso8601(),
      "start_hour" => "07",
      "start_min" => "00",
      "end_hour" => "15",
      "end_min" => "00",
      "shift_start" => "07:00",
      "shift_end" => "15:00",
      "hours" => "8.00",
      "rate" => :erlang.float_to_binary(rate * 1.0, decimals: 2),
      "notes" => ""
    }
  end

  defp minutes_between(start_s, end_s) do
    with {:ok, st} <- parse_hhmm(start_s),
         {:ok, en} <- parse_hhmm(end_s) do
      {:ok, en - st}
    else
      _ -> :error
    end
  end

  defp parse_hhmm(<<h::binary-size(2), ":", m::binary-size(2)>>) do
    with {hh, ""} <- Integer.parse(h),
         {mm, ""} <- Integer.parse(m),
         true <- hh in 0..23,
         true <- mm in 0..59 do
      {:ok, hh * 60 + mm}
    else
      _ -> :error
    end
  end

  defp parse_hhmm(_), do: :error

  defp validate_params(params, selected_full_name, hours_text) do
    full_name = (params["full_name"] || selected_full_name || "") |> String.trim()
    date = (params["date"] || "") |> String.trim()
    rate = (params["rate"] || "") |> String.trim()
    shift_start = (params["shift_start"] || "") |> String.trim()
    shift_end = (params["shift_end"] || "") |> String.trim()

    shift_time_ok? =
      case minutes_between(shift_start, shift_end) do
        {:ok, mins} when mins > 0 -> true
        _ -> false
      end

    errors =
      %{}
      |> add_err_if(full_name == "", :full_name, "select an employee")
      |> add_err_if(not valid_iso_date?(date), :date, "must be YYYY-MM-DD")
      |> add_err_if(not shift_time_ok?, :shift_time, "end must be after start")
      |> add_err_if(hours_text in [nil, ""], :hours, "hours could not be calculated")
      |> add_err_if(rate == "" or not valid_float_nonneg?(rate), :rate, "must be a number >= 0")

    {params, errors}
  end

  defp valid_iso_date?(s), do: match?({:ok, _}, Date.from_iso8601(s))

  defp valid_float_nonneg?(s) do
    case Float.parse(s) do
      {n, ""} when n >= 0 -> true
      _ -> false
    end
  end

  defp load_entries(""), do: []

  defp load_entries(full_name) do
    Core.hours_for_employee(full_name)
    |> Enum.sort_by(fn {Hours, _n, date, _ss, _se, _rate, _h, _notes} -> date end, :desc)
    |> Enum.take(25)
  end

  defp load_summary(""), do: %{hours_text: "0.00", gross_text: "0.00"}

  defp load_summary(full_name) do
    {h, g} = Core.current_period_totals(full_name)

    %{
      hours_text: :erlang.float_to_binary(h * 1.0, decimals: 2),
      gross_text: :erlang.float_to_binary(Core.money_round(g), decimals: 2)
    }
  end

  defp parse_float!(s) do
    case Float.parse(to_string(s)) do
      {n, _} -> n
      _ -> 0.0
    end
  end

  defp pad2(v), do: v |> to_string() |> String.pad_leading(2, "0") |> String.slice(0, 2)

  defp add_err_if(errors, true, field, msg), do: Map.put(errors, field, msg)
  defp add_err_if(errors, false, _field, _msg), do: errors
end
