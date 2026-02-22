defmodule PayrollWeb.SetupLive do
  use PayrollWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    settings = Core.company_settings()

    {:ok,
     socket
     |> assign(:form, to_form(atom_map_to_params(settings), as: :setup))
     |> assign(:errors, %{})
     |> assign(:preview, Core.settings_preview(settings))}
  end

  @impl true
  def handle_event("validate", %{"setup" => params}, socket) do
    {data, errors} = validate_params(params)

    {:noreply,
     socket
     |> assign(:form, to_form(atom_map_to_params(data), as: :setup))
     |> assign(:errors, errors)
     |> assign(:preview, Core.settings_preview(data))}
  end

  @impl true
  def handle_event("save", %{"setup" => params}, socket) do
    {data, errors} = validate_params(params)

    if map_size(errors) > 0 do
      {:noreply,
       socket
       |> assign(:form, to_form(atom_map_to_params(data), as: :setup))
       |> assign(:errors, errors)
       |> assign(:preview, Core.settings_preview(data))}
    else
      :ok = Core.save_company_settings(data)
      {:noreply, redirect(socket, to: "/app")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-xl mx-auto">
      <h1 class="text-2xl font-semibold">Company Setup</h1>
      <p class="mt-2 text-sm text-gray-600">
        Set up your company once to enable pay periods and payroll calculations.
      </p>

      <.form for={@form} phx-change="validate" phx-submit="save" class="mt-6 space-y-4">
        <div>
          <label class="block text-sm font-medium">Company name</label>
          <input name="setup[name]" value={@form[:name].value} class="mt-1 w-full border rounded p-2" />
          <%= error_line(@errors, :name) %>
        </div>

        <div>
          <label class="block text-sm font-medium">Province</label>
          <input name="setup[province]" value={@form[:province].value} class="mt-1 w-full border rounded p-2" />
          <%= error_line(@errors, :province) %>
        </div>

        <div>
          <label class="block text-sm font-medium">Address — optional</label>
          <textarea
            name="setup[address]"
            class="mt-1 w-full border rounded p-2"
            rows="3"
          ><%= @form[:address].value %></textarea>
          <%= error_line(@errors, :address) %>
        </div>

        <div>
          <label class="block text-sm font-medium">Phone — optional</label>
          <input
            name="setup[phone]"
            value={@form[:phone].value}
            class="mt-1 w-full border rounded p-2"
            placeholder="604-555-1234"
            inputmode="tel"
          />
          <%= error_line(@errors, :phone) %>
        </div>

        <div>
          <label class="block text-sm font-medium">Email — optional</label>
          <input
            name="setup[email]"
            value={@form[:email].value}
            class="mt-1 w-full border rounded p-2"
            placeholder="payroll@example.com"
            inputmode="email"
          />
          <%= error_line(@errors, :email) %>
        </div>

        <div>
          <label class="block text-sm font-medium">Business Number (BN) — optional</label>
          <input
            name="setup[business_number]"
            value={@form[:business_number].value}
            class="mt-1 w-full border rounded p-2"
            placeholder="123456789"
            inputmode="numeric"
          />
          <%= error_line(@errors, :business_number) %>
          <p class="mt-1 text-xs text-gray-500">9 digits. Leave blank if not available yet.</p>
        </div>

        <div>
          <label class="block text-sm font-medium">Payroll account (RP) — optional</label>
          <input
            name="setup[payroll_account_rp]"
            value={@form[:payroll_account_rp].value}
            class="mt-1 w-full border rounded p-2"
            placeholder="123456789RP0001"
          />
          <%= error_line(@errors, :payroll_account_rp) %>
          <p class="mt-1 text-xs text-gray-500">Format: 9 digits + RP + 4 digits.</p>
        </div>

        <div>
          <label class="block text-sm font-medium">GST/HST account (RT) — optional</label>
          <input
            name="setup[gst_account_rt]"
            value={@form[:gst_account_rt].value}
            class="mt-1 w-full border rounded p-2"
            placeholder="123456789RT0001"
          />
          <%= error_line(@errors, :gst_account_rt) %>
          <p class="mt-1 text-xs text-gray-500">Format: 9 digits + RT + 4 digits.</p>
        </div>

        <div>
          <label class="block text-sm font-medium">Anchor payday (YYYY-MM-DD)</label>
          <input
            name="setup[anchor_payday]"
            value={@form[:anchor_payday].value}
            class="mt-1 w-full border rounded p-2"
            placeholder="2023-01-13"
          />
          <%= error_line(@errors, :anchor_payday) %>
          <p class="mt-1 text-xs text-gray-500">
            Used to generate biweekly pay periods and detect 26/27 pay years.
          </p>
        </div>

        <div class="rounded border p-4 bg-gray-50">
          <h2 class="text-sm font-semibold">Schedule preview</h2>

          <div class="mt-3 text-sm space-y-2">
            <div>
              <span class="text-gray-600">Next paydays:</span>
              <span class="font-medium"><%= @preview.next_paydays_text %></span>
            </div>

            <div>
              <span class="text-gray-600">This year pay periods:</span>
              <span class="font-medium"><%= @preview.periods_per_year_text %></span>
            </div>

            <div>
              <span class="text-gray-600">Policy:</span>
              <span class="font-medium">
                start = payday <%= @preview.start_offset_text %>,
                cutoff = payday <%= @preview.cutoff_offset_text %>
              </span>
            </div>
          </div>
        </div>

        <div class="flex gap-3">
          <button type="submit" class="px-4 py-2 rounded bg-black text-white">
            Save &amp; continue
          </button>

          <a href="/app" class="px-4 py-2 rounded border">
            Back
          </a>
        </div>
      </.form>
    </div>
    """
  end

  defp validate_params(params) do
    bn = (params["business_number"] || "") |> String.trim()
    rp = (params["payroll_account_rp"] || "") |> String.trim()
    rt = (params["gst_account_rt"] || "") |> String.trim()

    address = (params["address"] || "") |> String.trim()
    phone = (params["phone"] || "") |> String.trim()
    email = (params["email"] || "") |> String.trim()

    data = %{
      name: (params["name"] || "") |> String.trim(),
      province: (params["province"] || "") |> String.trim(),
      pay_frequency: :biweekly,
      anchor_payday: (params["anchor_payday"] || "") |> String.trim(),
      period_start_offset_days: -20,
      period_cutoff_offset_days: -7,
      business_number: bn,
      payroll_account_rp: rp,
      gst_account_rt: rt,
      address: address,
      phone: phone,
      email: email
    }

    errors =
      %{}
      |> add_err_if(data.name == "", :name, "required")
      |> add_err_if(data.province == "", :province, "required")
      |> add_err_if(not valid_iso_date?(data.anchor_payday), :anchor_payday, "must be YYYY-MM-DD")
      |> add_err_if(bn != "" and not Regex.match?(~r/^\d{9}$/, bn), :business_number, "must be 9 digits")
      |> add_err_if(rp != "" and not Regex.match?(~r/^\d{9}RP\d{4}$/i, rp), :payroll_account_rp, "format: #########RP####")
      |> add_err_if(rt != "" and not Regex.match?(~r/^\d{9}RT\d{4}$/i, rt), :gst_account_rt, "format: #########RT####")
      |> add_err_if(phone != "" and not valid_phone?(phone), :phone, "invalid phone")
      |> add_err_if(email != "" and not valid_email?(email), :email, "invalid email")

    {data, errors}
  end

  defp valid_iso_date?(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # very light phone validation (allows digits, space, +, -, (), ext markers)
  defp valid_phone?(s) do
    Regex.match?(~r/^[0-9\+\-\(\)\s\.xextEXT]{7,}$/u, s)
  end

  # light email validation
  defp valid_email?(s) do
    Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/u, s)
  end

  defp add_err_if(errors, true, field, msg), do: Map.put(errors, field, msg)
  defp add_err_if(errors, false, _field, _msg), do: errors

  defp error_line(errors, field) do
    case Map.get(errors, field) do
      nil -> ""
      msg -> Phoenix.HTML.raw(~s(<p class="text-sm text-red-600 mt-1">#{msg}</p>))
    end
  end

  # Phoenix treats maps passed to to_form/2 as params; params must have string keys.
  defp atom_map_to_params(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {to_string(k), normalize_form_value(v)}
    end)
  end

  defp normalize_form_value(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_form_value(nil), do: ""
  defp normalize_form_value(v), do: v
end
