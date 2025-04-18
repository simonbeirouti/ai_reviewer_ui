defmodule AiReviewerWeb.PatternsLive do
  use AiReviewerWeb, :live_view
  alias AiReviewer.CodeReview
  alias AiReviewer.CodeReview.AntiPattern
  alias AiReviewer.Accounts

  @impl true
  def mount(_params, session, socket) do
    current_user = if session["user_id"] do
      Accounts.get_user!(session["user_id"])
    end

    patterns = if current_user do
      CodeReview.list_anti_patterns(current_user)
    else
      []
    end

    changeset = CodeReview.change_anti_pattern(%AntiPattern{})

    {:ok,
     assign(socket,
       patterns: patterns,
       changeset: changeset,
       page_title: "Anti-Patterns",
       current_user: current_user,
       current_path: "/dashboard/patterns"
     )}
  end

  @impl true
  def handle_event("save", %{"anti_pattern" => anti_pattern_params}, socket) do
    params = Map.put(anti_pattern_params, "user_id", socket.assigns.current_user.id)

    case CodeReview.create_anti_pattern(params) do
      {:ok, _anti_pattern} ->
        patterns = CodeReview.list_anti_patterns(socket.assigns.current_user)

        {:noreply,
         socket
         |> put_flash(:info, "Anti-pattern created successfully")
         |> assign(:patterns, patterns)
         |> assign(:changeset, CodeReview.change_anti_pattern(%AntiPattern{}))
         |> push_event("reset_form", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    anti_pattern = CodeReview.get_anti_pattern!(id)

    if anti_pattern.user_id == socket.assigns.current_user.id do
      {:ok, _} = CodeReview.delete_anti_pattern(anti_pattern)
      patterns = CodeReview.list_anti_patterns(socket.assigns.current_user)

      {:noreply,
       socket
       |> put_flash(:info, "Anti-pattern deleted successfully")
       |> assign(:patterns, patterns)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You can only delete your own anti-patterns")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="md:flex md:items-center md:justify-between">
        <div class="flex-1 min-w-0">
          <h2 class="text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate">
            My Anti-Patterns
          </h2>
        </div>
      </div>

      <div class="mt-8">
        <div class="bg-white shadow sm:rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg leading-6 font-medium text-gray-900">Add New Anti-Pattern</h3>
            <div class="mt-5">
              <.form
                :let={f}
                for={@changeset}
                phx-submit="save"
                class="space-y-6"
                id="anti-pattern-form"
                phx-hook="ResetOnSuccess"
              >
                <div>
                  <.input field={f[:name]} type="text" label="Name" required />
                </div>

                <div>
                  <.input
                    field={f[:language]}
                    type="select"
                    label="Language"
                    options={[
                      {"Elixir", "elixir"},
                      {"Python", "python"},
                      {"JavaScript", "javascript"},
                      {"TypeScript", "typescript"},
                      {"Ruby", "ruby"},
                      {"Go", "go"},
                      {"Rust", "rust"},
                      {"Java", "java"}
                    ]}
                    required
                  />
                </div>

                <div>
                  <.input
                    field={f[:description]}
                    type="textarea"
                    label="Description"
                    required
                  />
                </div>

                <div>
                  <.input
                    field={f[:content]}
                    type="textarea"
                    label="Content (Markdown)"
                    required
                  />
                </div>

                <div>
                  <button
                    type="submit"
                    class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                  >
                    Save Anti-Pattern
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <div class="mt-8">
          <div class="bg-white shadow sm:rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900">Your Anti-Patterns</h3>
              <div class="mt-5">
                <div class="flex flex-col">
                  <div class="-my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
                    <div class="py-2 align-middle inline-block min-w-full sm:px-6 lg:px-8">
                      <div class="shadow overflow-hidden border-b border-gray-200 sm:rounded-lg">
                        <table class="min-w-full divide-y divide-gray-200">
                          <thead class="bg-gray-50">
                            <tr>
                              <th
                                scope="col"
                                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                              >
                                Name
                              </th>
                              <th
                                scope="col"
                                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                              >
                                Language
                              </th>
                              <th
                                scope="col"
                                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                              >
                                Description
                              </th>
                              <th scope="col" class="relative px-6 py-3">
                                <span class="sr-only">Actions</span>
                              </th>
                            </tr>
                          </thead>
                          <tbody class="bg-white divide-y divide-gray-200">
                            <%= for pattern <- @patterns do %>
                              <tr>
                                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                                  <%= pattern.name %>
                                </td>
                                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                                  <%= pattern.language %>
                                </td>
                                <td class="px-6 py-4 text-sm text-gray-500">
                                  <%= pattern.description %>
                                </td>
                                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                                  <button
                                    phx-click="delete"
                                    phx-value-id={pattern.id}
                                    class="text-red-600 hover:text-red-900"
                                    data-confirm="Are you sure you want to delete this pattern?"
                                  >
                                    Delete
                                  </button>
                                </td>
                              </tr>
                            <% end %>
                          </tbody>
                        </table>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
