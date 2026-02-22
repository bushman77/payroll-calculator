defmodule PayrollWeb.EmployeeEditLive do
  use PayrollWeb, :live_view

  @impl true
  def mount(%{"full_name" => full_name} = params, _session, socket) do
    full_name = URI.decode(full_name)
    show = params["show_sin"] in ["1", "true", "on", "yes"]

    case Employee.get(full_name) do
      {:ok, emp} ->
        emp_params =
          emp
          |> Map.from_struct()
          # do not prefill sin by default
          |> Map.delete(:sin)
          |> atom_map_to_params()
          |> ensure_defaults()

        emp_params =
          if show do
            sin = emp |> Map.get(:sin, "") |> to_string() |> String.trim()
            Map.put(emp_params, "sin", sin)
          else
            emp_params
          end

        {:ok,
         socket
         |> assign(:full_name, full_name)
         |> assign(:emp, emp)
         |> assign(:show_sin, show)
         |> assign(:emp_params, emp_params)
         |> assign(:errors, %{})
         |> assign(:form, to_form(emp_params, as: :emp))}

      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, "Employee not found") |> redirect(to: "/employees")}
    end
  end

  @impl true
  def handle_event("toggle_sin", _params, socket) do
    full_name = socket.assigns.full_name

    to =
      if socket.assigns.show_sin do
        "/employees/#{URI.encode(full_name)}?show_sin=0"
      else
        "/employees/#{URI.encode(full_name)}?show_sin=1"
      end

    {:noreply, redirect(socket, to: to)}
  end

  @impl true
  def handle_event("validate", %{"emp" => params}, socket) do
    {data, errors} = validate_edit(params, socket.assigns.show_sin)

    {:noreply,
     socket
     |> assign(:emp_params, data)
     |> assign(:errors, errors)
     |> assign(:form, to_form(data, as: :emp))}
  end

  @impl true
  def handle_event("save", %{"emp" => params}, socket) do
    {data, errors} = validate_edit(params, socket.assigns.show_sin)

    if map_size(errors) > 0 do
      {:noreply,
       socket
       |> assign(:emp_params, data)
       |> assign(:errors, errors)
       |> assign(:form, to_form(data, as: :emp))}
    else
      # If SIN is hidden, ensure it is not sent (prevents wiping).
      data =
        if socket.assigns.show_sin do
          data
        else
          Map.delete(data, "sin")
        end

      {:ok, updated} = Employee.update(socket.assigns.full_name, data)

      {:noreply,
       socket
       |> assign(:emp, updated)
       |> put_flash(:info, "Saved")
       |> redirect(to: "/employees")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-xl mx-auto space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold">Edit Employee</h1>
          <p class="text-sm text-gray-600"><%= @full_name %></p>
        </div>

        <a href="/employees" class="px-3 py-2 rounded border text-sm">
          Back
        </a>
      </div>

      <div class="rounded border p-4">
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-3">
          <div>
            <label class="block text-sm font-medium">Hourly rate</label>
            <input name="emp[hourly_rate]" value={@form[:hourly_rate].value} class="mt-1 w-full border rounded p-2" />
            <%= error_line(@errors, :hourly_rate) %>
          </div>

          <div>
            <label class="block text-sm font-medium">Status</label>
            <select name="emp[status]" class="mt-1 w-full border rounded p-2">
              <option value="active" selected={@form[:status].value == "active"}>active</option>
              <option value="inactive" selected={@form[:status].value == "inactive"}>inactive</option>
            </select>
          </div>

          <hr class="my-2" />

          <div>
            <label class="block text-sm font-medium">Address line 1</label>
            <input name="emp[address1]" value={@form[:address1].value} class="mt-1 w-full border rounded p-2" />
          </div>

          <div>
            <label class="block text-sm font-medium">Address line 2</label>
            <input name="emp[address2]" value={@form[:address2].value} class="mt-1 w-full border rounded p-2" />
          </div>

          <div>
            <label class="block text-sm font-medium">City</label>
            <input name="emp[city]" value={@form[:city].value} class="mt-1 w-full border rounded p-2" />
          </div>

          <div>
            <label class="block text-sm font-medium">Province</label>
            <input name="emp[province]" value={@form[:province].value} class="mt-1 w-full border rounded p-2" placeholder="BC" />
          </div>

          <div>
            <label class="block text-sm font-medium">Postal code</label>
            <input name="emp[postalcode]" value={@form[:postalcode].value} class="mt-1 w-full border rounded p-2" placeholder="V1V 1V1" />
          </div>

          <hr class="my-2" />

          <div>
            <label class="block text-sm font-medium">Home phone</label>
            <input name="emp[home_phone]" value={@form[:home_phone].value} class="mt-1 w-full border rounded p-2" inputmode="tel" />
            <%= error_line(@errors, :home_phone) %>
          </div>

          <div>
            <label class="block text-sm font-medium">Alternate phone</label>
            <input name="emp[alternate_phone]" value={@form[:alternate_phone].value} class="mt-1 w-full border rounded p-2" inputmode="tel" />
          </div>

          <div>
            <label class="block text-sm font-medium">Email</label>
            <input name="emp[email]" value={@form[:email].value} class="mt-1 w-full border rounded p-2" inputmode="email" />
            <%= error_line(@errors, :email) %>
          </div>

          <hr class="my-2" />

          <div class="rounded border p-3 bg-gray-50">
            <div class="flex items-center justify-between gap-3">
              <div>
                <div class="text-sm font-medium">SIN</div>
                <div class="text-sm text-gray-600">
                  <%= masked_sin(@emp) %>
                </div>
              </div>

              <button type="button" phx-click="toggle_sin" class="px-3 py-2 rounded border text-sm">
                <%= if @show_sin, do: "Hide", else: "Reveal" %>
              </button>
            </div>

            <%= if @show_sin do %>
              <div class="mt-3">
                <label class="block text-sm font-medium">Edit SIN</label>
                <input name="emp[sin]" value={@form[:sin].value} class="mt-1 w-full border rounded p-2" inputmode="numeric" placeholder="123456789" />
                <%= error_line(@errors, :sin) %>
              </div>
            <% end %>
          </div>

          <div class="flex gap-3 pt-2">
            <button type="submit" class="px-4 py-2 rounded bg-black text-white">Save</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  # ---------- validation ----------

  defp validate_edit(params, show_sin?) do
    params = ensure_defaults(params)

    rate_s = (params["hourly_rate"] || "") |> String.trim()
    phone = (params["home_phone"] || "") |> String.trim()
    email = (params["email"] || "") |> String.trim()
    sin = (params["sin"] || "") |> String.trim()

    errors =
      %{}
      |> add_err_if(
        rate_s != "" and not valid_rate?(rate_s),
        :hourly_rate,
        "must be a number >= 0"
      )
      |> add_err_if(phone != "" and not valid_phone?(phone), :home_phone, "invalid phone")
      |> add_err_if(email != "" and not valid_email?(email), :email, "invalid email")
      |> add_err_if(
        show_sin? and sin != "" and not Regex.match?(~r/^\d{9}$/, sin),
        :sin,
        "must be 9 digits"
      )

    data =
      params
      |> Map.put("hourly_rate", rate_s)
      |> Map.put("home_phone", phone)
      |> Map.put("email", email)
      |> Map.put("sin", sin)

    {data, errors}
  end

  defp ensure_defaults(params) do
    Map.merge(
      %{
        "hourly_rate" => "",
        "status" => "active",
        "address1" => "",
        "address2" => "",
        "city" => "",
        "province" => "",
        "postalcode" => "",
        "home_phone" => "",
        "alternate_phone" => "",
        "email" => ""
      },
      params
    )
  end

  defp valid_rate?(s) do
    case Float.parse(s) do
      {n, ""} when n >= 0 -> true
      _ -> false
    end
  end

  defp valid_phone?(s), do: Regex.match?(~r/^[0-9\+\-\(\)\s\.xextEXT]{7,}$/u, s)
  defp valid_email?(s), do: Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/u, s)

  defp add_err_if(errors, true, field, msg), do: Map.put(errors, field, msg)
  defp add_err_if(errors, false, _field, _msg), do: errors

  defp error_line(errors, field) do
    case Map.get(errors, field) do
      nil -> ""
      msg -> Phoenix.HTML.raw(~s(<p class="text-sm text-red-600 mt-1">#{msg}</p>))
    end
  end

  defp atom_map_to_params(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize_form_value(v)} end)
  end

  defp normalize_form_value(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_form_value(nil), do: ""
  defp normalize_form_value(v), do: v

  defp masked_sin(emp) do
    sin =
      emp
      |> Map.get(:sin, "")
      |> to_string()
      |> String.trim()
      |> String.replace(~r/\D+/, "")

    cond do
      sin == "" ->
        "(none)"

      true ->
        last3 = last_n_chars(sin, 3)
        "*** *** " <> last3
    end
  end

  defp last_n_chars(s, n) when is_binary(s) and is_integer(n) and n > 0 do
    len = String.length(s)

    if len <= n do
      s
    else
      start = len - n
      {_, rest} = String.split_at(s, start)
      rest
    end
  end
end
