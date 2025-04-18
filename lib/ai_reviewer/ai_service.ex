defmodule AiReviewer.AiService do
  @moduledoc """
  Service module for interacting with OpenAI API
  """

  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage

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
