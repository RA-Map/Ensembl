#!/bin/sh

# following functiontaken from 
# http://stackoverflow.com/questions/3878624/how-do-i-programmatically-determine-if-there-are-uncommited-changes
function require_clean_work_tree () {
  # Update the index
  git update-index -q --ignore-submodules --refresh
  err=0

  # Disallow unstaged changes in the working tree
  if ! git diff-files --quiet --ignore-submodules --; then
    echo >&2 "!! Cannot $1: you have unstaged changes."
    git diff-files --name-status -r --ignore-submodules -- >&2
    err=1
  fi

  # Disallow uncommitted changes in the index
  if ! git diff-index --cached --quiet HEAD --ignore-submodules --;  then
    echo >&2 "!! Cannot $1: your index contains uncommitted changes."
    git diff-index --cached --name-status -r --ignore-submodules HEAD -- >&2
    err=1
  fi

  if [ $err = 1 ]; then
    echo >&2 "!! Please commit/stash them and retry this command"
    exit 1
  fi
}

function checkout() {
  branch=$1
  echo "*  Checking out $branch"
  git checkout $branch
  if [[ $? -ne 0 ]]; then
    echo "!! Git checkout of $branch branch failed" 1>&2
    exit 4
  fi
}

function pull() {
  branch=$1
  echo "*  Pulling in remote $branch"
  git pull $branch
  if [[ $? -ne 0 ]]; then
    echo "!! Git pull of $branch remote failed" 1>&2
    exit 5
  fi
}

function no_ff_merge() {
  branch=$1
  echo "*  Merge current branch with $branch"
  git merge --no-ff --log -m "Automatic merging of $branch" $branch
  if [[ $? -ne 0 ]]; then
    echo "Git merge with $branch failed" 1>&2
    exit 6
  fi
}

function uptodate_check() {
  branch=$1
  echo "*  Checking that $branch is at the same rev as origin/$branch"
  git fetch origin
  local_hash=$(git rev-parse $branch)
  remote_hash=$(git rev-parse origin/$branch)
  if [[ "$local_hash" != "$remote_hash" ]]; then
    echo "Git local ($local_hash) and remote ($remote_hash) are not the same" 1>&2
    echo "Rerun this script to rebase to the new remote $branch HEAD" 1>&2
    exit 6
  fi
}

function push() {
  echo "*  Pushing to origin"
  git push
  if [[ $? -ne 0 ]]; then
    echo "Git push to origin failed" 1>&2
    exit 7
  fi
}

# Exit if the repo is not under git control
git rev-parse
if [[ $? -ne 0 ]]; then
  echo "!! Current directory is not under git control. Exiting" 1>&2
  exit 1
fi

if [ $# -ne 1 ]; then
  echo >&2 "!! No branch given. Usage is"
  echo >&2 "!! ens-remotebranch-mergepush.sh BRANCH_NAME"
  exit 1
fi

target_branch=$1
if [ -z "$NO_PROMPT" ]; then
  echo "* Target branch we are working with is '$target_branch'"
  read -p "* Press return to continue (ctrl+c to abort)... " -s
  echo
fi

# Exit if we do not have a branch
git show-ref --verify --quiet refs/heads/$target_branch
if [[ $? -ne 0 ]]; then
  echo "!! The branch $target_branch does not exist. Cannot continue as there is nothing to merge" 1>&2
  exit 2
fi

# Do the master checkout & pull
checkout 'master'
pull 'origin'

# Switch to branch and ensure the tree is clean
checkout $target_branch
require_clean_work_tree 'merge'

# Switch to master. Ensure we are not behind origin/master and merge
checkout 'master'
uptodate_check 'master'
no_ff_merge $target_branch

# Get the user to check the merge
if [ -z "$NO_PROMPT" ]; then
  echo "*  Please take a moment to review your changes."
  echo "*  Example cmd: git log --oneline --reverse master..$target_branch"
  read -p "*  Press return to continue (ctrl+c to abort)... " -s
fi

if [ -z "$NO_PROMPT" ]; then
  echo "* About to push to origin"
  read -p "* Press return to continue (ctrl+c to abort)... " -s
  echo
fi

push

#Go back to target branch
checkout $target_branch

echo "*  Finished merge and push"