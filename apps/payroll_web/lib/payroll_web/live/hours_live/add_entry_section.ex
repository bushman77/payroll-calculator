defmodule PayrollWeb.HoursLive.AddEntrySection do
  use Phoenix.Component

  alias PayrollWeb.HoursLive.AddEntrySection.CalculatedHours
  alias PayrollWeb.HoursLive.AddEntrySection.DatePicker
  alias PayrollWeb.HoursLive.AddEntrySection.ShiftTimes
  alias PayrollWeb.HoursLive.AddEntrySection.Rate
  alias PayrollWeb.HoursLive.AddEntrySection.Notes

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :minutes, :list, required: true
  attr :hours_options, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-4">
      <h2 class="text-sm font-semibold">Add entry</h2>

      <.form for={@form} phx-change="validate" phx-submit="save" class="mt-4 space-y-3">
        <input type="hidden" name="h[full_name]" value={@form[:full_name].value} />

        <!-- Hours is calculated; still submitted -->
        <DatePicker.render form={@form} errors={@errors} />

    <ShiftTimes.render
    form={@form}
    errors={@errors}
    minutes={@minutes}
    hours_options={@hours_options}
    />

        <!-- Calculated hours display (read-only) -->
        <CalculatedHours.render form={@form} errors={@errors} />
    <div class="grid grid-cols-2 gap-3">
    <Rate.render form={@form} errors={@errors} />
    <Notes.render form={@form} />
    </div>
        <div class="pt-2">
          <button type="submit" class="px-4 py-2 rounded bg-black text-white">Save</button>
        </div>
      </.form>
    </div>
    """
  end

  defp error_line(errors, field) do
    case Map.get(errors, field) do
      nil -> ""
      msg -> Phoenix.HTML.raw(~s(<p class="text-sm text-red-600 mt-1">#{msg}</p>))
    end
  end
end
