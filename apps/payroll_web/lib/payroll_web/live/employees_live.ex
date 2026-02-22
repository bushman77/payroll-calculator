defmodule PayrollWeb.EmployeesLive do
  use PayrollWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:employees, load_employees())
     |> assign(:form, to_form(default_params(), as: :emp))
     |> assign(:errors, %{})}
  end

  @impl true
  def handle_event("validate", %{"emp" => params}, socket) do
    {data, errors} = validate_params(params)

    {:noreply,
     socket
     |> assign(:form, to_form(data, as: :emp))
     |> assign(:errors, errors)}
  end

  @impl true
  def handle_event("create", %{"emp" => params}, socket) do
    {data, errors} = validate_params(params)

    if map_size(errors) > 0 do
      {:noreply,
       socket
       |> assign(:form, to_form(data, as: :emp))
       |> assign(:errors, errors)}
    else
      case Employee.create(data) do
        {:ok, _full_name} ->
          {:noreply,
           socket
           |> assign(:employees, load_employees())
           |> assign(:form, to_form(default_params(), as: :emp))
           |> assign(:errors, %{})
           |> put_flash(:info, "Employee added")}

        {:error, reason} ->
          {:noreply,
           socket |> assign(:errors, Map.put(errors, :form, "create failed: #{inspect(reason)}"))}
      end
    end
  end

  @impl true
  def handle_event("deactivate", %{"name" => full_name}, socket) do
    _ = Employee.deactivate(full_name)

    {:noreply,
     socket
     |> assign(:employees, load_employees())
     |> put_flash(:info, "Employee deactivated")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-xl mx-auto space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold">Employees</h1>
          <p class="text-sm text-gray-600">Add employees and maintain contact info.</p>
        </div>

        <a href="/app" class="px-3 py-2 rounded border text-sm">
          Back
        </a>
      </div>

      <div class="rounded border p-4">
        <h2 class="text-sm font-semibold">Add employee</h2>

        <.form for={@form} phx-change="validate" phx-submit="create" class="mt-4 space-y-3">
          <div class="grid grid-cols-1 gap-3">
            <div>
              <label class="block text-sm font-medium">First name</label>
              <input name="emp[givenname]" value={@form[:givenname].value} class="mt-1 w-full border rounded p-2" />
              <%= error_line(@errors, :givenname) %>
            </div>

            <div>
              <label class="block text-sm font-medium">Last name</label>
              <input name="emp[surname]" value={@form[:surname].value} class="mt-1 w-full border rounded p-2" />
              <%= error_line(@errors, :surname) %>
            </div>

            <div>
              <label class="block text-sm font-medium">Hourly rate</label>
              <input name="emp[hourly_rate]" value={@form[:hourly_rate].value} class="mt-1 w-full border rounded p-2" placeholder="25.00" inputmode="decimal" />
              <%= error_line(@errors, :hourly_rate) %>
            </div>

            <hr class="my-2" />

            <div>
              <label class="block text-sm font-medium">Address line 1</label>
              <input name="emp[address1]" value={@form[:address1].value} class="mt-1 w-full border rounded p-2" />
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

            <div>
              <label class="block text-sm font-medium">Phone</label>
              <input name="emp[home_phone]" value={@form[:home_phone].value} class="mt-1 w-full border rounded p-2" inputmode="tel" />
              <%= error_line(@errors, :home_phone) %>
            </div>

            <div>
              <label class="block text-sm font-medium">Email</label>
              <input name="emp[email]" value={@form[:email].value} class="mt-1 w-full border rounded p-2" inputmode="email" />
              <%= error_line(@errors, :email) %>
            </div>

            <div>
              <label class="block text-sm font-medium">SIN</label>
              <input name="emp[sin]" value={@form[:sin].value} class="mt-1 w-full border rounded p-2" inputmode="numeric" placeholder="123456789" />
              <%= error_line(@errors, :sin) %>
              <p class="mt-1 text-xs text-gray-500">Stored for payroll. Not shown in lists.</p>
            </div>
          </div>

          <%= error_line(@errors, :form) %>

          <div class="flex gap-3 pt-2">
            <button type="submit" class="px-4 py-2 rounded bg-black text-white">Add</button>
          </div>
        </.form>
      </div>

      <div class="rounded border p-4">
        <h2 class="text-sm font-semibold">Active employees</h2>

        <div class="mt-3 space-y-2">
          <%= if @employees == [] do %>
            <p class="text-sm text-gray-600">No employees yet.</p>
          <% else %>
            <%= for {full_name, emp} <- @employees do %>
              <div class="flex items-center justify-between gap-3 border rounded p-3">
                <div class="min-w-0">
                  <div class="font-medium truncate"><%= full_name %></div>
                  <div class="text-sm text-gray-600">
                    Rate: <%= format_money(Map.get(emp, :hourly_rate, 0.0)) %>
                    · Status: <%= Atom.to_string(Map.get(emp, :status, :active)) %>
                  </div>
                </div>

                <div class="flex gap-2">
                  <a href={"/employees/#{URI.encode(full_name)}"} class="px-3 py-2 rounded border text-sm">Edit</a>

                  <button type="button" phx-click="deactivate" phx-value-name={full_name} class="px-3 py-2 rounded border text-sm">
                    Deactivate
                  </button>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ----------------------------
  # helpers
  # ----------------------------
  defp load_employees, do: Employee.active()

  defp default_params do
    %{
      "givenname" => "",
      "surname" => "",
      "hourly_rate" => "",
      "address1" => "",
      "city" => "",
      "province" => "",
      "postalcode" => "",
      "home_phone" => "",
      "email" => "",
      "sin" => ""
    }
  end

  defp validate_params(params) do
    given = (params["givenname"] || "") |> String.trim()
    sur = (params["surname"] || "") |> String.trim()
    rate_s = (params["hourly_rate"] || "") |> String.trim()

    phone = (params["home_phone"] || "") |> String.trim()
    email = (params["email"] || "") |> String.trim()
    sin = (params["sin"] || "") |> String.trim()

    errors =
      %{}
      |> add_err_if(given == "", :givenname, "required")
      |> add_err_if(sur == "", :surname, "required")
      |> add_err_if(rate_s == "", :hourly_rate, "required")
      |> add_err_if(
        rate_s != "" and not valid_rate?(rate_s),
        :hourly_rate,
        "must be a number >= 0"
      )
      |> add_err_if(phone != "" and not valid_phone?(phone), :home_phone, "invalid phone")
      |> add_err_if(email != "" and not valid_email?(email), :email, "invalid email")
      |> add_err_if(sin != "" and not Regex.match?(~r/^\d{9}$/, sin), :sin, "must be 9 digits")

    data =
      params
      |> Map.put("givenname", given)
      |> Map.put("surname", sur)
      |> Map.put("hourly_rate", rate_s)
      |> Map.put("home_phone", phone)
      |> Map.put("email", email)
      |> Map.put("sin", sin)

    {data, errors}
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

  defp format_money(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_money(n) when is_integer(n), do: format_money(n * 1.0)
  defp format_money(_), do: "0.00"
end
