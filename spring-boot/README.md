# Smart Build Script for Spring Boot/Maven Projects

This script optimizes your Spring Boot application's build process by intelligently selecting and running only the most relevant tests based on your code changes.

## Features

- AI-powered test selection based on code changes
- Integrates seamlessly with Maven build lifecycle
- Supports custom Maven goals
- Progressive confidence levels (80%, 95%, 99%, 99.9%)
- Compatible with CI/CD environments

## Prerequisites

- Bash-compatible environment
- Java JDK (version required by your Spring Boot project)
- Maven (3.6+ recommended) or Maven Wrapper
- [jq](https://stedolan.github.io/jq/download/) for JSON processing
- [GitHub CLI](https://cli.github.com/) (optional, enhances PR diff analysis in CI)
- OpenAI API key

## Setup

1. Copy the `shortest.sh` script to your Spring Boot project's root directory (where your `pom.xml` is located).

2. Make the script executable:
   ```
   chmod +x smart_build.sh
   ```

3. Set up your OpenAI API key:
   - Create a `.env` file in your project root:
     ```
     PERSONAL_OPENAI_API_KEY=your_api_key_here
     ```
   - Or export it in your shell:
     ```
     export PERSONAL_OPENAI_API_KEY=your_api_key_here
     ```

## Usage

Run the script with your desired Maven goals:

```
./smart_build.sh [maven_goals]
```

Examples:
- Default (clean and install): `./smart_build.sh`
- Custom goals: `./smart_build.sh clean test`
- Spring Boot run: `./smart_build.sh spring-boot:run`

The script will:
1. Analyze your code changes
2. Determine relevant tests
3. Run selected tests using Maven
4. Progress through confidence levels if needed

## Integration with CI/CD

To use in a CI/CD pipeline (e.g., GitHub Actions):

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up JDK
        uses: actions/setup-java@v2
        with:
          java-version: '11'  # Adjust as needed
          distribution: 'adopt'
      - name: Run Smart Build
        env:
          PERSONAL_OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: ./smart_build.sh clean install
```

Ensure you set the `OPENAI_API_KEY` secret in your CI/CD environment.

## Customization

Adjust the confidence levels or other parameters by modifying the `shortest_build()` function in the script.

## Notes

- The script uses GPT-4 to analyze changes and select tests. Ensure your OpenAI API key has access to the GPT-4 model.
- For large projects, consider the potential impact on API usage and associated costs.
- Always verify the script's effectiveness for your specific project before relying on it for critical builds.

## License

[MIT License](LICENSE)