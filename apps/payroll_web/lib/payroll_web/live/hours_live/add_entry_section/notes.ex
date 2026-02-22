defmodule PayrollWeb.HoursLive.AddEntrySection.Notes do
  use Phoenix.Component

  attr :form, :any, required: true

  def render(assigns) do
    ~H"""
    <div class="col-span-2 sm:col-span-1">
      <label class="block text-sm font-medium">Notes</label>
      <input
        name="h[notes]"
        value={@form[:notes].value}
        class="mt-1 w-full border rounded p-2 text-base bg-white text-black"
      />
    </div>
    """
  end
end
