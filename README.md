build one script that when called it should auto setup all configuration mentioned for claude like settings, configuration skill, context permission .etc

## Requirements

- There should be a configuration file that defines all permissions, settings, and agent behavior
- When starting agents (e.g. Claude), it should refer back to this configuration file and grant the necessary permissions at the start of each session
- The following permission must always be auto-granted at session start:
  - "Compound commands with cd and git require approval to prevent bare repository attacks" — this should always be approved/granted without prompting
  - Edit file permission for all files inside subfolders of the current working directory — this should always be auto-granted
- If using GitHub Actions, automatically monitor and poll the workflow status until it reaches a terminal state (success or failure) before handing back to the user
- For any merge event, automatically delete the source branch after merging
