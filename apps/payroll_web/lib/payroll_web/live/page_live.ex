defmodule PayrollWeb.Components.Calendar do
  use Surface.Component

  slot(default, required: true)

  def render(assigns) do
    ~F"""
    <table class="border-double">
      <thead>
        <td class="w-1/6">Sunday</td>
        <td class="w-1/6">Monday</td>
        <td class="w-1/6">Tuesday</td>
        <td class="w-1/6">Wednesday</td>
        <td class="w-1/6">Thursday</td>
        <td class="w-1/6">Friday</td>
        <td class="w-1/6">Saturday</td>
      </thead>
      <tbody>
        <tr>
          <td>1</td>
        </tr>
      </tbody>
    </table>
    """
  end
end

defmodule PageLive do
  use Surface.LiveView
  alias PayrollWeb.Components.Calendar

  def render(assigns) do
    ~F"""
    <Calendar>
      Hi there!
    </Calendar>
    """
  end
end
