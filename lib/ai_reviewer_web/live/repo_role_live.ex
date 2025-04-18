defmodule AiReviewerWeb.RepoRoleLive do
  use AiReviewerWeb, :live_view
  alias AiReviewer.Accounts

  def mount(%{"repo_name" => repo_name}, session, socket) do
    current_user = if session["user_id"] do
      Accounts.get_user!(session["user_id"])
    end

    {:ok, assign(socket,
      repo_name: repo_name,
      current_user: current_user,
      page_title: "Select Role - #{repo_name}",
      current_path: "/dashboard/repo/#{repo_name}"
    )}
  end

  def handle_event("select_role", %{"role" => role}, socket) do
    case role do
      "reviewer" ->
        {:noreply, push_navigate(socket, to: ~p"/dashboard/repo/#{socket.assigns.repo_name}/reviewer")}
      "tester" ->
        {:noreply, push_navigate(socket, to: ~p"/dashboard/repo/#{socket.assigns.repo_name}/tester")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 py-12">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="text-center mb-12">
          <h1 class="text-3xl font-bold text-gray-900 mb-2">Select Your Role</h1>
          <p class="text-lg text-gray-600">Choose how you want to interact with <%= @repo_name %></p>
        </div>

        <div class="grid grid-cols-1 gap-8 md:grid-cols-2 max-w-4xl mx-auto">
          <!-- Code Reviewer Card -->
          <div class="bg-white rounded-lg shadow-lg overflow-hidden hover:shadow-xl transition-shadow duration-300">
            <div class="p-6">
              <div class="flex items-center justify-center w-16 h-16 bg-blue-100 rounded-full mx-auto mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
              </div>
              <h2 class="text-2xl font-bold text-center text-gray-900 mb-4">Code Reviewer</h2>
              <p class="text-gray-600 text-center mb-6">
                Review code changes, get AI-powered suggestions, and manage pull requests with intelligent feedback.
              </p>
              <ul class="space-y-3 text-sm text-gray-600 mb-6">
                <li class="flex items-center">
                  <svg class="h-5 w-5 text-green-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  AI-powered code analysis
                </li>
                <li class="flex items-center">
                  <svg class="h-5 w-5 text-green-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  Pull request management
                </li>
                <li class="flex items-center">
                  <svg class="h-5 w-5 text-green-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  Automated code suggestions
                </li>
              </ul>
              <button
                phx-click="select_role"
                phx-value-role="reviewer"
                class="w-full bg-blue-600 text-white py-3 px-4 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors duration-300"
              >
                Continue as Reviewer
              </button>
            </div>
          </div>

          <!-- Code Tester Card -->
          <div class="bg-white rounded-lg shadow-lg overflow-hidden hover:shadow-xl transition-shadow duration-300">
            <div class="p-6">
              <div class="flex items-center justify-center w-16 h-16 bg-purple-100 rounded-full mx-auto mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
                </svg>
              </div>
              <h2 class="text-2xl font-bold text-center text-gray-900 mb-4">Code Tester</h2>
              <p class="text-gray-600 text-center mb-6">
                Generate comprehensive test cases, validate code behavior, and ensure robust test coverage.
              </p>
              <ul class="space-y-3 text-sm text-gray-600 mb-6">
                <li class="flex items-center">
                  <svg class="h-5 w-5 text-green-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  AI-generated test cases
                </li>
                <li class="flex items-center">
                  <svg class="h-5 w-5 text-green-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  Test coverage analysis
                </li>
                <li class="flex items-center">
                  <svg class="h-5 w-5 text-green-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  Edge case detection
                </li>
              </ul>
              <button
                phx-click="select_role"
                phx-value-role="tester"
                class="w-full bg-purple-600 text-white py-3 px-4 rounded-md hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:ring-offset-2 transition-colors duration-300"
              >
                Continue as Tester
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
