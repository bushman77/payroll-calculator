defmodule PayrollWeb.HoursLive do
  use PayrollWeb, :live_view

  alias PayrollWeb.HoursLive.RecentEntriesSection
  alias PayrollWeb.HoursLive.AddEntrySection
  alias PayrollWeb.HoursLive.EmployeeSection
  alias PayrollWeb.HoursLive.Header

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

    {:ok,
     socket
     |> assign(:minutes, @minutes)
     |> assign(:hours_options, hours_options())
     |> assign(:employees, employees)
     |> assign(:selected, selected)
     |> assign(:entries, load_entries(selected))
     |> assign(:summary, load_summary(selected))
     |> assign(:errors, %{})
     |> assign(:form, to_form(form_params, as: :h))}
  end

  @impl true
  def handle_event("select_employee", %{"employee" => full_name}, socket) do
    form_params = default_params(full_name)

    {:noreply,
     socket
     |> assign(:selected, full_name)
     |> assign(:entries, load_entries(full_name))
     |> assign(:summary, load_summary(full_name))
     |> assign(:errors, %{})
     |> assign(:form, to_form(form_params, as: :h))}
  end

  @impl true
  def handle_event("validate", %{"h" => params}, socket) do
    params = normalize_time_fields(params)
    params = put_shift_times(params)
    params = put_auto_hours(params)

    {data, errors} = validate_params(params, socket.assigns.selected)

    {:noreply,
     socket
     |> assign(:errors, errors)
     |> assign(:form, to_form(data, as: :h))}
  end

  @impl true
  def handle_event("save", %{"h" => params}, socket) do
    params = normalize_time_fields(params)
    params = put_shift_times(params)
    params = put_auto_hours(params)

    {data, errors} = validate_params(params, socket.assigns.selected)

    if map_size(errors) > 0 do
      {:noreply,
       socket
       |> assign(:errors, errors)
       |> assign(:form, to_form(data, as: :h))}
    else
      :ok =
        Core.add_hours_entry(%{
          full_name: data["full_name"],
          date: data["date"],
          shift_start: data["shift_start"],
          shift_end: data["shift_end"],
          rate: parse_float!(data["rate"]),
          hours: parse_float!(data["hours"]),
          notes: data["notes"]
        })

      full_name = socket.assigns.selected
      fresh = default_params(full_name)

      {:noreply,
       socket
       |> put_flash(:info, "Hours saved")
       |> assign(:entries, load_entries(full_name))
       |> assign(:summary, load_summary(full_name))
       |> assign(:errors, %{})
       |> assign(:form, to_form(fresh, as: :h))}
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
        />

        <RecentEntriesSection.render entries={@entries} />
      <% end %>
    </div>
    """
  end

  # ---------------- helpers ----------------

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

  defp normalize_time_fields(params) do
    params
    |> Map.put("start_hour", pad2(Map.get(params, "start_hour", "07")))
    |> Map.put("start_min", pad2(Map.get(params, "start_min", "00")))
    |> Map.put("end_hour", pad2(Map.get(params, "end_hour", "15")))
    |> Map.put("end_min", pad2(Map.get(params, "end_min", "00")))
  end

  defp put_shift_times(params) do
    start = "#{params["start_hour"]}:#{params["start_min"]}"
    endt = "#{params["end_hour"]}:#{params["end_min"]}"

    params
    |> Map.put("shift_start", start)
    |> Map.put("shift_end", endt)
  end

  defp put_auto_hours(params) do
    start_s = params["shift_start"] || ""
    end_s = params["shift_end"] || ""

    hours =
      case minutes_between(start_s, end_s) do
        {:ok, mins} when mins > 0 ->
          :erlang.float_to_binary(mins / 60.0, decimals: 2)

        _ ->
          ""
      end

    Map.put(params, "hours", hours)
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

  defp validate_params(params, selected_full_name) do
    full_name = (params["full_name"] || selected_full_name || "") |> String.trim()
    date = (params["date"] || "") |> String.trim()
    shift_start = (params["shift_start"] || "") |> String.trim()
    shift_end = (params["shift_end"] || "") |> String.trim()
    hours = (params["hours"] || "") |> String.trim()
    rate = (params["rate"] || "") |> String.trim()

    errors =
      %{}
      |> add_err_if(full_name == "", :full_name, "select an employee")
      |> add_err_if(not valid_iso_date?(date), :date, "must be YYYY-MM-DD")
      |> add_err_if(
        minutes_between(shift_start, shift_end) in [:error, {:ok, 0}] or
          not end_after_start?(shift_start, shift_end),
        :shift_time,
        "end must be after start"
      )
      |> add_err_if(hours == "", :hours, "hours could not be calculated")
      |> add_err_if(rate == "" or not valid_float_nonneg?(rate), :rate, "must be a number >= 0")

    data =
      params
      |> Map.put("full_name", full_name)
      |> Map.put("date", date)
      |> Map.put("shift_start", shift_start)
      |> Map.put("shift_end", shift_end)
      |> Map.put("hours", hours)
      |> Map.put("rate", rate)
      |> Map.put_new("notes", "")

    {data, errors}
  end

  defp valid_iso_date?(s), do: match?({:ok, _}, Date.from_iso8601(s))

  defp valid_float_nonneg?(s) do
    case Float.parse(s) do
      {n, ""} when n >= 0 -> true
      _ -> false
    end
  end

  defp end_after_start?(start_s, end_s) do
    case minutes_between(start_s, end_s) do
      {:ok, mins} when mins > 0 -> true
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
