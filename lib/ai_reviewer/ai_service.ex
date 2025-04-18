defmodule AiReviewer.AiService do
  @moduledoc """
  Service module for interacting with OpenAI API
  """

  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage

  @doc """
  Generates ExUnit tests for the given source code using OpenAI.
  Returns the generated test code.
  """
  def generate_tests(source_code, file_path) do
    # Initialize OpenAI client
    openai = OpenaiEx.new(System.fetch_env!("LB_OPENAI_API_KEY"))
    |> OpenaiEx.with_receive_timeout(45_000)

    # Create chat completion request
    chat_req = Chat.Completions.new(
      model: "gpt-3.5-turbo",
      messages: [
        ChatMessage.system("""
        You are an expert Elixir developer specializing in writing comprehensive test suites.
        You analyze code and create thorough ExUnit tests following best practices.
        """),
        ChatMessage.user("""
        Generate comprehensive ExUnit tests for the following Elixir code.
        Follow these guidelines:
        1. Create tests for all public functions
        2. Include doctests if the functions have documentation
        3. Add appropriate test setup if needed
        4. Test edge cases and error conditions
        5. Follow Elixir testing best practices
        6. Use descriptive test names
        7. Group related tests using describe blocks
        8. Add comments explaining complex test scenarios
        9. Include any necessary test helpers
        10. Ensure proper assertions are used

        Source file: #{file_path}

        Source code:
        ```elixir
        #{source_code}
        ```

        Generate a complete test file with appropriate test cases.
        """)
      ]
    )

    # Call OpenAI API
    case Chat.Completions.create(openai, chat_req) do
      {:ok, response} ->
        content = response["choices"]
        |> List.first()
        |> Map.get("message")
        |> Map.get("content")

        # Extract the code block from the response if it exists
        case Regex.run(~r/```elixir\s*([\s\S]*?)\s*```/, content) do
          [_, code] -> {:ok, code}
          nil -> {:ok, content}  # If no code block, use the entire response
        end

      {:error, error} ->
        {:error, "OpenAI API error: #{inspect(error)}"}
    end
  end

  @doc """
  Reviews code changes and suggests improvements based on anti-patterns and best practices.
  Returns the modified code with comments explaining the changes.
  """
  def review_code(code_changes, anti_patterns, language) do
    # Construct the prompt
    prompt = build_review_prompt(code_changes, anti_patterns, language)

    # Initialize OpenAI client
    openai = OpenaiEx.new(System.fetch_env!("LB_OPENAI_API_KEY"))
    |> OpenaiEx.with_receive_timeout(45_000)

    # Create chat completion request
    chat_req = Chat.Completions.new(
      model: "gpt-3.5-turbo",
      messages: [
        ChatMessage.system("""
        You are an expert code reviewer focusing on identifying and fixing code issues.
        You analyze code based on provided anti-patterns and best practices.
        For each issue you find:
        1. Add a comment above the problematic code explaining the issue
        2. Add your suggested fix below the comment
        3. Keep the rest of the code unchanged
        4. DO NOT include any markdown code block, only return the code with the comments and changes.

        Return ONLY the modified code with your comments and changes.
        Do not include any other text or explanations outside of the code comments and do not include any markdown code block, only return the code with the comments and changes.
        """),
        ChatMessage.user(prompt)
      ]
    )

    # Call OpenAI API
    case Chat.Completions.create(openai, chat_req) do
      {:ok, response} ->
        # Access string keys from the response
        content = response["choices"]
        |> List.first()
        |> Map.get("message")
        |> Map.get("content")
        {:ok, content}
      {:error, error} ->
        {:error, "OpenAI API error: #{inspect(error)}"}
    end
  end

  defp build_review_prompt(code_changes, anti_patterns, language) do
    anti_pattern_text = Enum.map_join(anti_patterns, "\n", fn pattern ->
      "#{pattern.name}:\n#{pattern.content}"
    end)

    """
    Please review the following #{language} code and suggest improvements:

    Anti-patterns to check:
    #{anti_pattern_text}

    Code to review:
    #{code_changes}

    Please analyze the code for:
    1. Matches with the provided anti-patterns
    2. General code quality issues
    3. Security concerns
    4. Performance implications
    5. Best practices specific to #{language}

    Return the code with your comments and improvements directly integrated.
    Add comments above any code you modify explaining the changes.
    """
  end
end
