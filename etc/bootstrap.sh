#!/bin/bash

#
#  _           _ _     _ _    _ _          _                 _       _
# | |         (_) |   | | |  (_) |        | |               | |     | |
# | |__  _   _ _| | __| | | ___| |_ ___   | |__   ___   ___ | |_ ___| |_ _ __ __ _ _ __
# | '_ \| | | | | |/ _` | |/ / | __/ _ \  | '_ \ / _ \ / _ \| __/ __| __| '__/ _` | '_ \
# | |_) | |_| | | | (_| |   <| | ||  __/  | |_) | (_) | (_) | |_\__ \ |_| | | (_| | |_) |
# |_.__/ \__,_|_|_|\__,_|_|\_\_|\__\___|  |_.__/ \___/ \___/ \__|___/\__|_|  \__,_| .__/
#                                                                                 | |
#                                                                                 |_|
# Based on:
# https://github.com/buildkite/agent/blob/master/templates/bootstrap.sh
# customised by glenngillen to work with Heroku build and deployment flows

# It's possible for a hook or a build script to change things like `set -eou
# pipefail`, causing our bootstrap.sh to misbehave, so this function will set
# them back to what we expect them to be.
function buildkite-flags-reset {
  # Causes this script to exit if a variable isn't present
  set -u

  # Ensure command pipes fail if any command fails (e.g. fail-cmd | success-cmd == fail)
  set -o pipefail

  # Turn off debugging
  set +x

  # If a command fails, don't exit, just keep on truckin'
  set +e
}

buildkite-flags-reset

##############################################################
#
# BOOTSTRAP FUNCTIONS
# These functions are used throughout the bootstrap.sh file
#
##############################################################

BUILDKITE_PROMPT="\033[90m$\033[0m"

# Shows the command being run, and runs it
function buildkite-prompt-and-run {
  echo -e "$BUILDKITE_PROMPT $1"
  eval "$1"
}

# Shows the command about to be run, and exits if it fails
function buildkite-run {
  echo -e "$BUILDKITE_PROMPT $1"
  eval "$1"
  EVAL_EXIT_STATUS=$?

  if [[ $EVAL_EXIT_STATUS -ne 0 ]]; then
    exit $EVAL_EXIT_STATUS
  fi
}

function buildkite-debug {
  if [[ "$BUILDKITE_AGENT_DEBUG" == "true" ]]; then
    echo -e "$1"
  fi
}

# Runs the command, but only output what it's doing if we're in DEBUG mode
function buildkite-run-debug {
  buildkite-debug "$BUILDKITE_PROMPT $1"
  eval "$1"
}

# Show an error and exit
function buildkite-error {
  echo -e "~~~ :rotating_light: \033[31mBuildkite Error\033[0m"
  echo "$1"
  exit 1
}

# Show a warning
function buildkite-warning {
  echo -e "\033[33m⚠️ Buildkite Warning: $1\033[0m"
  echo "^^^ +++"
}

# Run a hook script
function buildkite-hook {
  HOOK_LABEL="$1"
  HOOK_SCRIPT_PATH="$2"

  if [[ -e "$HOOK_SCRIPT_PATH" ]]; then
    # Print to the screen we're going to run the hook
    echo "~~~ Running $HOOK_LABEL hook"
    echo -e "$BUILDKITE_PROMPT .\"$HOOK_SCRIPT_PATH\""

    # Store the current folder, so after the hook, we can return back to the
    # current working directory
    HOOK_PREVIOUS_WORKING_DIR=$(pwd)

    # Run the hook
    . "$HOOK_SCRIPT_PATH"
    HOOK_EXIT_STATUS=$?

    # Reset the bootstrap.sh flags
    buildkite-flags-reset

    # Return back to the working dir
    cd "$HOOK_PREVIOUS_WORKING_DIR"

    # Exit from the bootstrap.sh script if the hook exits with a non-0 exit
    # status
    if [[ $HOOK_EXIT_STATUS -ne 0 ]]; then
      echo "Hook returned an exit status of $HOOK_EXIT_STATUS, exiting..."
      exit $HOOK_EXIT_STATUS
    fi
  elif [[ "$BUILDKITE_AGENT_DEBUG" == "true" ]]; then
    # When in debug mode, show that we've skipped a hook
    echo "~~~ Running $HOOK_LABEL hook"
    echo "Skipping, no hook script found at: $HOOK_SCRIPT_PATH"
  fi
}

function buildkite-global-hook {
  buildkite-hook "global $1" "$BUILDKITE_HOOKS_PATH/$1"
}

function buildkite-local-hook {
  buildkite-hook "local $1" ".buildkite/hooks/$1"
}

##############################################################
#
# PATH DEFAULTS
# Come up with the paths used throughout the bootstrap.sh file
#
##############################################################

# Add the $BUILDKITE_BIN_PATH to the $PATH
export PATH="$BUILDKITE_BIN_PATH:$PATH"

# Come up with the place that the repository will be checked out to
SANITIZED_AGENT_NAME=$(echo "$BUILDKITE_AGENT_NAME" | tr -d '"')
PROJECT_FOLDER_NAME="$SANITIZED_AGENT_NAME/$BUILDKITE_PROJECT_SLUG"
export BUILDKITE_BUILD_CHECKOUT_PATH="$BUILDKITE_BUILD_PATH/$PROJECT_FOLDER_NAME"

if [[ "$BUILDKITE_AGENT_DEBUG" == "true" ]]; then
  echo "~~~ Build environment variables"

  buildkite-run "env | grep BUILDKITE | sort"
fi

##############################################################
#
# ENVIRONMENT SETUP
# A place for people to set up environment variables that
# might be needed for their build scripts, such as secret
# tokens and other information.
#
##############################################################

buildkite-global-hook "environment"

##############################################################
#
# REPOSITORY HANDLING
# Creates the build folder and makes sure we're running the
# build at the right commit.
#
##############################################################

# TODO: Seems this isn't available during build :( Need to find an alternative approach
#if [ ! -f /etc/heroku/dyno ]; then
#  buildkite-error "Dyno metadata not found. Contact brett@heroku.com and ask for runtime-dyno-metadata to be enabled for this app."
#fi
#GIT_SHA=$(sed -e 's/^.*"commit":"\([a-f0-9]\+\)".*$/\1/' /etc/heroku/dyno)
#if [ -z "$GIT_SHA" ]; then
#  buildkite-error "Dyno metadata does not include a commit SHA, unable to verify we have the correct build."
#else
#  if [ "$BUILDKITE_COMMIT" == "$GIT_SHA" ]; then
#    buildkite-debug "Dyno is running the correct code."
#  else
#    buildkite-error "Dyno codebase ($GIT_SHA) doesn't match expected commit SHA of $BUILDKITE_COMMIT"
#  fi
#fi

# TODO: Work out Heroku approximations of the following
# Grab author and commit information and send it back to Buildkite
#buildkite-debug "~~~ Saving Git information"
#buildkite-run-debug "buildkite-agent meta-data set \"buildkite:git:commit\" \"\`git show \"$BUILDKITE_COMMIT\" -s --format=fuller --no-color\`\""
#buildkite-run-debug "buildkite-agent meta-data set \"buildkite:git:branch\" \"\`git branch --contains \"$BUILDKITE_COMMIT\" --no-color\`\""

# Store the current value of BUILDKITE_BUILD_CHECKOUT_PATH, so we can detect if
# one of the post-checkout hooks changed it.
PREVIOUS_BUILDKITE_BUILD_CHECKOUT_PATH=$BUILDKITE_BUILD_CHECKOUT_PATH

# Run the `post-checkout` hook
buildkite-global-hook "post-checkout"

# Now that we have a repo, we can perform a `post-checkout` local hook
buildkite-local-hook "post-checkout"

# If the BUILDKITE_BUILD_CHECKOUT_PATH has been changed, log and switch to it
if [[ "$PREVIOUS_BUILDKITE_BUILD_CHECKOUT_PATH" != "$BUILDKITE_BUILD_CHECKOUT_PATH" ]]; then
  echo "~~~ A post-checkout hook has changed the build path to $BUILDKITE_BUILD_CHECKOUT_PATH"

  if [ -d "$BUILDKITE_BUILD_CHECKOUT_PATH" ]; then
    buildkite-run "cd $BUILDKITE_BUILD_CHECKOUT_PATH"
  else
    buildkite-error "Failed to switch to \"$BUILDKITE_BUILD_CHECKOUT_PATH\" as it doesn't exist"
  fi
fi

##############################################################
#
# RUN THE BUILD
# Determines how to run the build, and then runs it
#
##############################################################

# Make sure we actually have a command to run
if [[ "$BUILDKITE_COMMAND" == "" ]]; then
  buildkite-error "No command has been defined. Please go to \"Project Settings\" and configure your build step's \"Command\""
fi

# Generate a temporary build script containing what to actually run.
buildkite-debug "~~~ Preparing build script"
BUILDKITE_SCRIPT_PATH="buildkite-script-$BUILDKITE_JOB_ID"

# Generate a different script depending on whether or not it's a script to
# execute
if [[ -f "$BUILDKITE_COMMAND" ]]; then
  # Make sure the script they're trying to execute has chmod +x. We can't do
  # this inside the script we generate because it fails within Docker:
  # https://github.com/docker/docker/issues/9547
  buildkite-run-debug "chmod +x \"$BUILDKITE_COMMAND\""
  echo -e '#!/bin/bash'"\n./\"$BUILDKITE_COMMAND\"" > "$BUILDKITE_SCRIPT_PATH"
else
  echo -e '#!/bin/bash'"\n$BUILDKITE_COMMAND" > "$BUILDKITE_SCRIPT_PATH"
fi

if [[ "$BUILDKITE_AGENT_DEBUG" == "true" ]]; then
  buildkite-run "cat $BUILDKITE_SCRIPT_PATH"
fi

# Ensure the temporary build script can be executed
chmod +x "$BUILDKITE_SCRIPT_PATH"

# If the command isn't a file on the filesystem, then it's something we need to
# eval. But before we even try running it, we should double check that the
# agent is allowed to eval commands.
#
# NOTE: There is a slight problem with this check - and it's with usage with
# Docker. If you specify a script to run inside the docker container, and that
# isn't on the file system at the same path, then it won't match, and it'll be
# treated as an eval. For example, you mount your repository at /app, and tell
# the agent run `app/ci.sh`, ci.sh won't exist on the filesytem at this point
# at app/ci.sh. The soltion is to make sure the `workdir` directroy of the
# docker container is at /app in that case.
if [[ ! -f "$BUILDKITE_COMMAND" ]]; then
  # Make sure the agent is even allowed to eval commands
  if [[ "$BUILDKITE_COMMAND_EVAL" != "true" ]]; then
    buildkite-error "This agent is not allowed to evaluate console commands. To allow this, re-run this agent without the \`--no-command-eval\` option, or specify a script within your repository to run instead (such as scripts/test.sh)."
  fi

  BUILDKITE_COMMAND_ACTION="Running command"
  BUILDKITE_COMMAND_DISPLAY=$BUILDKITE_COMMAND
else
  BUILDKITE_COMMAND_ACTION="Running build script"
  BUILDKITE_COMMAND_DISPLAY="./\"$BUILDKITE_COMMAND\""
fi

# Run the global `pre-command` hook
buildkite-global-hook "pre-command"

# Run the per-checkout `pre-command` hook
buildkite-local-hook "pre-command"

# If the user has specificed their own command hook
if [[ -e "$BUILDKITE_HOOKS_PATH/command" ]]; then
  buildkite-global-hook "command"

  # Capture the exit status from the build script
  export BUILDKITE_COMMAND_EXIT_STATUS=$?
else
  ## Docker
  if [[ ! -z "${BUILDKITE_DOCKER:-}" ]] && [[ "$BUILDKITE_DOCKER" != "" ]]; then
    DOCKER_CONTAINER="buildkite_${BUILDKITE_JOB_ID}_container"
    DOCKER_IMAGE="buildkite_${BUILDKITE_JOB_ID}_image"

    function docker-cleanup {
      echo "~~~ Cleaning up Docker containers"
      buildkite-run "docker rm -f -v $DOCKER_CONTAINER || true"
    }

    trap docker-cleanup EXIT

    # Build the Docker image, namespaced to the job
    echo "~~~ Building Docker image $DOCKER_IMAGE"

    buildkite-run "docker build -f ${BUILDKITE_DOCKER_FILE:-Dockerfile} -t $DOCKER_IMAGE ."

    # Run the build script command in a one-off container
    echo "~~~ $BUILDKITE_COMMAND_ACTION (in Docker container)"
    buildkite-prompt-and-run "docker run --name $DOCKER_CONTAINER $DOCKER_IMAGE \"./$BUILDKITE_SCRIPT_PATH\""

    # Capture the exit status from the build script
    export BUILDKITE_COMMAND_EXIT_STATUS=$?

  ## Docker Compose
  elif [[ ! -z "${BUILDKITE_DOCKER_COMPOSE_CONTAINER:-}" ]] && [[ "$BUILDKITE_DOCKER_COMPOSE_CONTAINER" != "" ]]; then
    # Compose strips dashes and underscores, so we'll remove them to match the docker container names
    COMPOSE_PROJ_NAME="buildkite"${BUILDKITE_JOB_ID//-}
    # The name of the docker container compose creates when it creates the adhoc run
    COMPOSE_CONTAINER_NAME=$COMPOSE_PROJ_NAME"_"$BUILDKITE_DOCKER_COMPOSE_CONTAINER
    COMPOSE_COMMAND="docker-compose -f ${BUILDKITE_DOCKER_COMPOSE_FILE:-docker-compose.yml} -p $COMPOSE_PROJ_NAME"

    function compose-cleanup {
      echo "~~~ Cleaning up Docker containers"
      buildkite-run "$COMPOSE_COMMAND kill || true"
      buildkite-run "$COMPOSE_COMMAND rm --force -v || true"

      # The adhoc run container isn't cleaned up by compose, so we have to do it ourselves
      buildkite-run "docker rm -f -v ${COMPOSE_CONTAINER_NAME}_run_1 || true"
    }

    trap compose-cleanup EXIT

    # Build the Docker images using Compose, namespaced to the job
    echo "~~~ Building Docker images"

    buildkite-run "$COMPOSE_COMMAND build"

    # Run the build script command in the service specified in BUILDKITE_DOCKER_COMPOSE_CONTAINER
    echo "~~~ $BUILDKITE_COMMAND_ACTION (in Docker Compose container)"
    buildkite-prompt-and-run "$COMPOSE_COMMAND run $BUILDKITE_DOCKER_COMPOSE_CONTAINER \"./$BUILDKITE_SCRIPT_PATH\""

    # Capture the exit status from the build script
    export BUILDKITE_COMMAND_EXIT_STATUS=$?

  ## Standard
  else
    echo "~~~ $BUILDKITE_COMMAND_ACTION"
    echo -e "$BUILDKITE_PROMPT $BUILDKITE_COMMAND_DISPLAY"
    ."/$BUILDKITE_SCRIPT_PATH"

    # Capture the exit status from the build script
    export BUILDKITE_COMMAND_EXIT_STATUS=$?

    # Reset the bootstrap.sh flags
    buildkite-flags-reset
  fi
fi

# Run the per-checkout `post-command` hook
buildkite-local-hook "post-command"

# Run the global `post-command` hook
buildkite-global-hook "post-command"

##############################################################
#
# ARTIFACTS
# Uploads and build artifacts associated with this build
#
##############################################################

if [[ "$BUILDKITE_ARTIFACT_PATHS" != "" ]]; then
  # Run the per-checkout `pre-artifact` hook
  buildkite-local-hook "pre-artifact"

  # Run the global `pre-artifact` hook
  buildkite-global-hook "pre-artifact"

  echo "~~~ Uploading artifacts"
  if [[ ! -z "${BUILDKITE_ARTIFACT_UPLOAD_DESTINATION:-}" ]] && [[ "$BUILDKITE_ARTIFACT_UPLOAD_DESTINATION" != "" ]]; then
    buildkite-prompt-and-run "buildkite-agent artifact upload \"$BUILDKITE_ARTIFACT_PATHS\" \"$BUILDKITE_ARTIFACT_UPLOAD_DESTINATION\""
  else
    buildkite-prompt-and-run "buildkite-agent artifact upload \"$BUILDKITE_ARTIFACT_PATHS\""
  fi

  # If the artifact upload fails, open the current group and exit with an error
  if [[ $? -ne 0 ]]; then
    echo "^^^ +++"
    exit 1
  fi
fi

# Be sure to exit this script with the same exit status that the users build
# script exited with.
exit $BUILDKITE_COMMAND_EXIT_STATUS
