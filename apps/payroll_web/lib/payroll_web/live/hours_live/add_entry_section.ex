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

  # controlled assigns
  attr :start_hour, :string, required: true
  attr :start_min, :string, required: true
  attr :end_hour, :string, required: true
  attr :end_min, :string, required: true
  attr :shift_start, :string, required: true
  attr :shift_end, :string, required: true
  attr :hours_text, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-4">
      <h2 class="text-sm font-semibold">Add entry</h2>

      <.form for={@form} phx-submit="save" class="mt-4 space-y-3">
        <input type="hidden" name="h[full_name]" value={@form.params["full_name"] || @form[:full_name].value} />

        <!-- keep hidden copies of controlled time state so submit always has a consistent snapshot -->
        <input type="hidden" name="h[start_hour]" value={@start_hour} />
        <input type="hidden" name="h[start_min]" value={@start_min} />
        <input type="hidden" name="h[end_hour]" value={@end_hour} />
        <input type="hidden" name="h[end_min]" value={@end_min} />
        <input type="hidden" name="h[shift_start]" value={@shift_start} />
        <input type="hidden" name="h[shift_end]" value={@shift_end} />
        <input type="hidden" name="h[hours]" value={@hours_text} />

        <DatePicker.render form={@form} errors={@errors} />

        <ShiftTimes.render
          minutes={@minutes}
          hours_options={@hours_options}
          start_hour={@start_hour}
          start_min={@start_min}
          end_hour={@end_hour}
          end_min={@end_min}
          shift_start={@shift_start}
          shift_end={@shift_end}
          errors={@errors}
        />

    <div class="text-xs text-gray-500">
    dbg start=<%= @shift_start %> end=<%= @shift_end %> hours=<%= @hours_text %>
    </div>

    <CalculatedHours.render
    hours_text={@hours_text}
    shift_start={@shift_start}
    shift_end={@shift_end}
    errors={@errors}
    />
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
end
