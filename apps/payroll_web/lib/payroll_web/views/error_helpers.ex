defmodule PayrollWeb.ErrorHelpers do
  @moduledoc false

  @doc """
  Minimal error tag helper.

  Returns a list of translated error strings for the given field.
  (You can turn these into HTML later when you actually build forms.)
  """
  def error_tag(form, field) do
    Keyword.get_values(form.errors, field)
    |> Enum.map(&translate_error/1)
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(PayrollWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(PayrollWeb.Gettext, "errors", msg, opts)
    end
  end
end
