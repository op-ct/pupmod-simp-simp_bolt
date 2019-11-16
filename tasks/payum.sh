#!/bin/sh

# This script checks if a specified version of puppet-agent is available from
# enabled yum repos. If not, it checks if any version of puppet-agent is
# available via yum and if so it determines the newest one.

# Check for specified version
yum --showduplicates list "puppet-agent-${PT_version}" >/dev/null 2>&1
if [ $? = 0 ]; then
  # Return specified version
  echo -n "$PT_version"
else
  # Determine most recent puppet-agent version
  version="$(yum --showduplicates list puppet-agent 2>/dev/null|grep puppet-agent|awk '{print $2}'|sort --version-sort|tail -1)"
  if [ -z "$version" ] ; then
    # Return 0 if puppet-agent is not found in available repos
    echo -n "0"
  else
    # Return most recent version of puppet-agent found in repos
    echo -n "${version}"
  fi
fi

