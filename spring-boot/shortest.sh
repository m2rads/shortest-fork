#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NO_COLOR='\033[0m'

# Default Maven goals
MAVEN_GOALS=${@:-clean install}

# Helper functions
print_message() { echo -e "\n${1}${2}${NO_COLOR}"; }
error_message() { print_message "${RED}" "ERROR: $1"; }
warning_message() { print_message "${YELLOW}" "WARNING: $1"; }
success_message() { print_message "${GREEN}" "SUCCESS: $1"; }
info_message() { print_message "${BLUE}" "INFO: $1"; }

# Function to get PR diff and local changes
get_combined_diff() {
  {
    git diff --cached
    git diff
    if command -v gh &>/dev/null && [[ -n "${CI:-}" ]]; then
      gh pr diff
    fi
  } | awk '/^diff --git/ {in_folder=($0 ~ " b/src/| b/pom.xml")} in_folder {print}'
}

# Function to get all test files
get_all_test_files() {
  find src/test/java/ca/bestbuy/digitalsignsystem -name '*Test.java' | sort
}

# Function to determine which test files to run based on confidence level
determine_test_files() {
  local confidence_level=$1
  local combined_diff=$(get_combined_diff)
  local all_test_files=$(get_all_test_files)

  info_message "Analyzing diff and test files for ${confidence_level}% confidence level..."

  local system_content="You are an expert Java developer that determines which test files should be run to achieve a ${confidence_level}% confidence level in the passing build. Analyze the provided diff and available test files to make your decision. If there are no test files worth running to get to the desired confidence level, return an empty array. Return only available test files. Consider the package structure: test files are organized under src/test/java/ca/bestbuy/digitalsignsystem/ with subfolders like config/, controller/, dtos/, services/, and testUtils/."

  local user_content="
Diff:
<diff>
${combined_diff}
</diff>

Available test files:
<test_files>
${all_test_files}
</test_files>"

  local payload=$(jq -n \
    --arg system_content "$system_content" \
    --arg user_content "$user_content" \
    '{
      model: "gpt-4o-2024-08-06",
      messages: [
        { role: "system", content: $system_content },
        { role: "user", content: $user_content }
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "test_files_to_run",
          schema: {
            type: "object",
            properties: {
              test_files: {
                type: "array",
                items: {
                  type: "string",
                  description: "Test file to run"
                }
              }
            },
            required: ["test_files"],
            additionalProperties: false
          },
          strict: true
        }
      }
    }')

  local response=$(curl -s -X POST https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${PERSONAL_OPENAI_API_KEY:-}" \
    -d "$payload")

  echo "$response" | jq -r '.choices[0].message.content | fromjson | .test_files[]' | grep -E '^src/test/java/ca/bestbuy/digitalsignsystem/.*Test\.java$' || true
}

# Function to determine specific tests to run within selected test files
determine_tests() {
  local confidence_level=$1
  shift
  local test_files=("$@")
  local combined_diff=$(get_combined_diff)
  local test_contents=""

  info_message "Analyzing specific tests within selected files for ${confidence_level}% confidence level..."

  for file in "${test_files[@]}"; do
    test_contents+="File: $file\n$(cat "$file")\n\n"
  done

  local system_content="You are an expert Java developer that determines which specific tests within the provided test files should be run to achieve a ${confidence_level}% confidence level in the passing build. Analyze the provided diff and test file contents to make your decision. Return the specific test method names to run in the format 'ClassName#testMethodName'."

  local user_content="
Diff:
<diff>
${combined_diff}
</diff>

Test file contents:
<test_contents>
${test_contents}
</test_contents>"

  local payload=$(jq -n \
    --arg system_content "$system_content" \
    --arg user_content "$user_content" \
    '{
      model: "gpt-4o-2024-08-06",
      messages: [
        { role: "system", content: $system_content },
        { role: "user", content: $user_content }
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "tests_to_run",
          schema: {
            type: "object",
            properties: {
              tests: {
                type: "array",
                items: {
                  type: "string",
                  description: "Specific test to run in format ClassName#testMethodName"
                }
              }
            },
            required: ["tests"],
            additionalProperties: false
          },
          strict: true
        }
      }
    }')

  local response=$(curl -s -X POST https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${PERSONAL_OPENAI_API_KEY:-}" \
    -d "$payload")

  echo "$response" | jq -r '.choices[0].message.content | fromjson | .tests[]' | grep -E '^[A-Za-z0-9]+Test#test[A-Za-z0-9]+$' || true
}

# Function to run tests based on confidence level
run_tests() {
  local confidence_level=$1

  info_message "Determining which test files to run for ${confidence_level}% confidence level..."

  local test_files=($(determine_test_files $confidence_level))

  if [ ${#test_files[@]} -eq 0 ]; then
    warning_message "No test files determined for ${confidence_level}% confidence level."
    return 0
  else
    info_message "Test files to run:"
    for file in "${test_files[@]}"; do
      echo "  - $file"
    done
  fi

  info_message "Determining specific tests to run within selected test files..."
  local tests_to_run=($(determine_tests $confidence_level "${test_files[@]}"))

  if [ ${#tests_to_run[@]} -eq 0 ]; then
    warning_message "No specific tests determined for ${confidence_level}% confidence level."
    return 0
  fi

  info_message "Running specific tests for ${confidence_level}% confidence level:"
  for test in "${tests_to_run[@]}"; do
    echo "  - $test"
  done

  # Construct Maven test command
  local test_classes=$(printf "%s," "${tests_to_run[@]}")
  test_classes=${test_classes%,}  # Remove trailing comma
  
  if command -v ./mvnw &>/dev/null; then
    ./mvnw $MAVEN_GOALS -Dtest=$test_classes -DfailIfNoTests=false
  else
    mvn $MAVEN_GOALS -Dtest=$test_classes -DfailIfNoTests=false
  fi
}

# Check if GitHub CLI is installed for PR diff (only in CI environment)
if [[ -n "${CI:-}" ]] && ! command -v gh &>/dev/null; then
  warning_message "GitHub CLI (gh) is not installed. PR diff analysis may be limited."
fi

# Source the .env file if it exists
if [ -f .env ]; then
  source .env
fi

# Check for PERSONAL_OPENAI_API_KEY
if [ -z "${PERSONAL_OPENAI_API_KEY:-}" ]; then
  error_message "PERSONAL_OPENAI_API_KEY is not set. Please set it in .env or export it"
  exit 1
fi

# Main function to run the shortest build
shortest_build() {
  local confidence_levels=(80 95 99 99.9)

  for level in "${confidence_levels[@]}"; do
    info_message "Running tests for ${level}% confidence level..."
    if ! run_tests $level; then
      error_message "Build failed at ${level}% confidence level."
      exit 1
    fi
    success_message "Tests passed for ${level}% confidence level."
  done

  success_message "All confidence levels passed successfully!"
}

# Run the shortest build
shortest_build